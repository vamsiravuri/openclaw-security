#!/usr/bin/env python3
"""
Skill Security Scanner — Supply Chain Defense for OpenClaw
Adapted from Hive Financial Systems skill_security_system.py

Scans SKILL.md files and bundled scripts for malicious patterns.
Uses Python 3 stdlib only — no pip dependencies required.

Usage:
  python3 scan_skill.py scan <file>           Scan a single file
  python3 scan_skill.py scan-dir <dir>        Scan all files in a skill folder
  python3 scan_skill.py check-name <name>     Check skill name against blocklist
  python3 scan_skill.py scan-all              Scan all installed skills
"""
import re
import json
import hashlib
import sys
from pathlib import Path
from datetime import datetime

# ── Critical Patterns (BLOCK on match) ─────────────────────────────
CRITICAL_PATTERNS = {
    # Direct malware indicators
    "base64_decode_exec": r"base64\s*-d.*\|\s*bash",
    "curl_pipe_bash": r"curl.*\|\s*(ba)?sh",
    "wget_pipe_bash": r"wget.*\|\s*(ba)?sh",
    "encoded_payload": r"echo\s+[A-Za-z0-9+/]{50,}.*base64",

    # Data exfiltration
    "curl_post_data": r"curl.*-X\s+POST.*-d\s+@",
    "webhook_exfil": r"webhook\.site",
    "pastebin_exfil": r"pastebin\.com/api",
    "external_ip_server": r"curl.*https?://\d+\.\d+\.\d+\.\d+",

    # Credential theft
    "env_file_read": r"cat.*\.env",
    "openclaw_config_read": r"cat.*(\.clawdbot|\.openclaw)",
    "ssh_key_read": r"cat.*\.ssh/(id_rsa|id_ed25519|authorized_keys)",
    "aws_creds_read": r"cat.*\.aws/credentials",
    "browser_data_theft": r"(Chrome|Firefox|Safari).*(Login Data|Cookies|key[34]\.db)",

    # Persistence mechanisms
    "crontab_modify": r"crontab\s+(-e|-l.*\|)",
    "launchd_persist": r"Library/LaunchAgents",
    "systemd_persist": r"systemctl.*(enable|daemon-reload)",
    "bashrc_modify": r"echo.*>>\s*\.(bashrc|zshrc|profile|bash_profile)",

    # Reverse shells
    "netcat_reverse": r"nc\s+-e\s+/bin/(ba)?sh",
    "bash_tcp": r"/dev/tcp/\d+\.\d+\.\d+\.\d+",
    "python_reverse_shell": r"socket\.connect.*exec",
    "socat_reverse": r"socat.*exec.*sh",

    # Obfuscation techniques
    "hex_encoded_command": r"\\x[0-9a-fA-F]{2}.*\\x[0-9a-fA-F]{2}.*\\x[0-9a-fA-F]{2}",
    "unicode_zero_width": r"[\u200B-\u200D\uFEFF]",
    "nested_command_sub": r"\$\(.*\$\(.*\)\)",

    # OpenClaw-specific threats
    "soul_md_overwrite": r"(>|write|echo).*SOUL\.md",
    "memory_md_overwrite": r"(>|write|echo).*MEMORY\.md",
    "openclaw_json_modify": r"(>|write|echo).*openclaw\.json",
}

# ── Suspicious Patterns (WARNING on match) ─────────────────────────
SUSPICIOUS_PATTERNS = {
    "downloads_zip": r"curl.*\.(zip|tar\.gz|tgz)",
    "chmod_777": r"chmod\s+(777|-R\s+777)",
    "sudo_nopasswd": r"NOPASSWD",
    "external_script_source": r"source\s+<\(curl",
    "tmp_execution": r"/tmp/.*&&\s+chmod\s+\+x",
    "npm_global_install": r"npm\s+install\s+-g",
    "pip_install": r"pip3?\s+install",
    "docker_privileged": r"docker\s+run\s+--privileged",
    "eval_usage": r"\beval\s*\(",
    "env_var_exfil": r"printenv|env\s*>",
}

# ── ClawHavoc Blocklist ────────────────────────────────────────────
BLOCKED_SKILLS = [
    "what-would-elon-do",
    "crypto-wallet-checker",
    "youtube-auto-subs",
    "clawhub-installer",
    "moltbot-updater",
    "token-optimizer",
    "free-gpt-bridge",
    "ai-auto-trader",
    "skill-booster-pro",
    "claude-jailbreak-v2",
    "claude-unfiltered",
    "devmode-enabler",
    "system-optimizer-pro",
    "auto-crypto-miner",
    "wallet-recovery-tool",
    "seed-phrase-checker",
    "nft-auto-minter",
    "defi-yield-optimizer",
]

BLOCKED_PATTERNS = [
    r"clawhub-\w{5}",
    r".*-wallet-.*",
    r".*-jailbreak.*",
    r".*-unfiltered.*",
    r".*-devmode.*",
    r"moltbot-\w+",
    r".*crypto-mine.*",
    r".*seed-phrase.*",
]


def scan_file(filepath):
    """Scan a single file for malicious patterns."""
    path = Path(filepath)
    if not path.exists():
        return {"file": str(path), "verdict": "ERROR", "message": "File not found"}

    content = path.read_text(errors="replace")
    threats = []

    for name, pattern in CRITICAL_PATTERNS.items():
        for match in re.finditer(pattern, content, re.IGNORECASE | re.MULTILINE):
            line_num = content[: match.start()].count("\n") + 1
            threats.append(
                {
                    "severity": "CRITICAL",
                    "pattern": name,
                    "matched": match.group(0)[:100],
                    "line": line_num,
                }
            )

    for name, pattern in SUSPICIOUS_PATTERNS.items():
        for match in re.finditer(pattern, content, re.IGNORECASE | re.MULTILINE):
            line_num = content[: match.start()].count("\n") + 1
            threats.append(
                {
                    "severity": "SUSPICIOUS",
                    "pattern": name,
                    "matched": match.group(0)[:100],
                    "line": line_num,
                }
            )

    critical_count = sum(1 for t in threats if t["severity"] == "CRITICAL")

    if critical_count > 0:
        verdict = "BLOCKED"
    elif len(threats) > 0:
        verdict = "WARNING"
    else:
        verdict = "CLEAN"

    return {
        "file": str(path),
        "verdict": verdict,
        "threats_total": len(threats),
        "critical": critical_count,
        "suspicious": len(threats) - critical_count,
        "threats": threats,
        "scanned_at": datetime.now().isoformat(),
    }


def scan_dir(dirpath):
    """Scan all files in a skill directory."""
    path = Path(dirpath)
    if not path.is_dir():
        return {"dir": str(path), "verdict": "ERROR", "message": "Not a directory"}

    results = []
    worst_verdict = "CLEAN"

    for f in sorted(path.rglob("*")):
        if f.is_file() and f.suffix in (
            ".md", ".sh", ".py", ".js", ".ts", ".json", ".yaml", ".yml", "",
        ):
            result = scan_file(f)
            results.append(result)
            if result["verdict"] == "BLOCKED":
                worst_verdict = "BLOCKED"
            elif result["verdict"] == "WARNING" and worst_verdict == "CLEAN":
                worst_verdict = "WARNING"

    return {
        "dir": str(path),
        "verdict": worst_verdict,
        "files_scanned": len(results),
        "results": results,
        "scanned_at": datetime.now().isoformat(),
    }


def check_name(skill_name):
    """Check skill name against blocklist."""
    name_lower = skill_name.lower().strip()

    # Direct blocklist match
    if name_lower in BLOCKED_SKILLS:
        return {
            "name": skill_name,
            "verdict": "BLOCKED",
            "reason": "Known malicious skill (ClawHavoc campaign)",
        }

    # Pattern match
    for pattern in BLOCKED_PATTERNS:
        if re.match(pattern, name_lower, re.IGNORECASE):
            return {
                "name": skill_name,
                "verdict": "BLOCKED",
                "reason": f"Matches malicious pattern: {pattern}",
            }

    # Typosquatting check
    suspicious_stems = ["clawhub", "openclaw", "moltbot", "clawdbot", "anthropic"]
    for stem in suspicious_stems:
        if stem in name_lower and name_lower != stem:
            return {
                "name": skill_name,
                "verdict": "WARNING",
                "reason": f"Possible typosquatting: contains '{stem}'",
            }

    return {"name": skill_name, "verdict": "CLEAN", "reason": "Not on blocklist"}


def scan_all_installed():
    """Scan all skills in ~/.openclaw/skills/."""
    skills_dir = Path.home() / ".openclaw" / "skills"
    if not skills_dir.exists():
        return {"verdict": "ERROR", "message": f"{skills_dir} does not exist"}

    results = []
    for skill_folder in sorted(skills_dir.iterdir()):
        if skill_folder.is_dir():
            skill_md = skill_folder / "SKILL.md"
            if skill_md.exists():
                # Check name first
                name_result = check_name(skill_folder.name)
                # Scan content
                dir_result = scan_dir(skill_folder)
                results.append(
                    {
                        "skill": skill_folder.name,
                        "name_check": name_result["verdict"],
                        "content_check": dir_result["verdict"],
                        "details": dir_result,
                    }
                )

    return {
        "skills_scanned": len(results),
        "results": results,
        "scanned_at": datetime.now().isoformat(),
    }


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    command = sys.argv[1]

    if command == "scan" and len(sys.argv) >= 3:
        result = scan_file(sys.argv[2])
    elif command == "scan-dir" and len(sys.argv) >= 3:
        result = scan_dir(sys.argv[2])
    elif command == "check-name" and len(sys.argv) >= 3:
        result = check_name(sys.argv[2])
    elif command == "scan-all":
        result = scan_all_installed()
    else:
        print(__doc__)
        sys.exit(1)

    print(json.dumps(result, indent=2))

    # Exit code: 0=clean, 1=warning, 2=blocked, 3=error
    verdict = result.get("verdict", "ERROR")
    if verdict == "CLEAN":
        sys.exit(0)
    elif verdict == "WARNING":
        sys.exit(1)
    elif verdict == "BLOCKED":
        sys.exit(2)
    else:
        sys.exit(3)


if __name__ == "__main__":
    main()
