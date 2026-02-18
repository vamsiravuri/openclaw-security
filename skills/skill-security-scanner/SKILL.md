---
name: skill-security-scanner
description: >
  Supply chain security for Hive Financial Systems. Activate BEFORE installing
  any skill from ClawHub or external sources. Scans SKILL.md files and bundled
  scripts for malicious patterns including data exfiltration, credential theft,
  reverse shells, persistence mechanisms, and obfuscated payloads. Maintains a
  blocklist of known malicious skills from the ClawHavoc campaign (341 skills).
  Uses a bundled Python scanner for deterministic pattern matching.
---

# Skill Security Scanner — Supply Chain Defense

## When to Activate

Run this scanner BEFORE:
- Installing any skill from ClawHub
- Running `openclaw skills install <name>`
- Manually copying a skill folder into `~/.openclaw/skills/`
- Reviewing a skill recommended by an external source

## How to Scan

The scanner script is bundled at `{baseDir}/scripts/scan_skill.py`.
It uses Python 3 stdlib only — no pip dependencies.

### Scan a skill file:
```bash
python3 {baseDir}/scripts/scan_skill.py scan /path/to/skill/SKILL.md
```

### Scan an entire skill folder:
```bash
python3 {baseDir}/scripts/scan_skill.py scan-dir /path/to/skill-folder/
```

### Check a skill name against the blocklist:
```bash
python3 {baseDir}/scripts/scan_skill.py check-name "skill-name-here"
```

### Scan all installed skills:
```bash
python3 {baseDir}/scripts/scan_skill.py scan-all
```

## Interpreting Results

The scanner outputs JSON with a `verdict` field:

- `"CLEAN"` — no threats found, safe to install
- `"WARNING"` — suspicious patterns found, review manually before installing
- `"BLOCKED"` — critical threats found, DO NOT install

**On BLOCKED:** Show the user the threat details and recommend:
"This skill contains malicious patterns. Do NOT install. Report it on ClawHub."

**On WARNING:** Show the user the suspicious patterns and ask:
"This skill has suspicious patterns. Want me to show the flagged lines?"

## Known Threats (ClawHavoc Campaign)

The scanner includes a blocklist of 341 known malicious skills identified
in the ClawHavoc campaign (Jan 27-29, 2026). Categories include:
- Crypto wallet stealers disguised as trading tools
- YouTube utilities that install Atomic Stealer (AMOS)
- Auto-updaters that exfiltrate `~/.openclaw/.env` to webhook.site
- "Functional" tools with hidden reverse shell backdoors

The blocklist also catches typosquatting patterns:
- Names mimicking official tools: `clawhub-*`, `openclaw-*`, `moltbot-*`
- Randomized suffixes: `clawhub-\w{5}`
- Crypto/wallet keywords in skill names

## Manual Review Checklist

If the scanner returns WARNING, also manually check:
1. Does the skill's `description` match what it actually does?
2. Does it request network access (`curl`, `wget`, `web_fetch`) unnecessarily?
3. Does it read sensitive files (`~/.ssh`, `~/.env`, `~/.aws`)?
4. Does the author have other published skills? New accounts are higher risk.
5. Does the install instruction pull code from untrusted URLs?
