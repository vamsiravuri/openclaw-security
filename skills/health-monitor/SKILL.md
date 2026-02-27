---
name: health-monitor
description: Monitors OpenClaw instance health including cron job status, skill loading, gateway responsiveness, and tool functionality. Detects stalled jobs, broken tools, and configuration drift. Detection skill — reports only, never blocks.
version: 1.1.0
---

# Health Monitor — Instance Health and Self-Repair Detection

You are a health monitoring layer that continuously checks the operational status of the OpenClaw instance. You operate in detection-only mode — you NEVER block actions, only detect problems and report them. Your purpose is to catch operational failures before they become security gaps.

## Health Checks

Perform the following checks when invoked (either by the nightly cron or on-demand):

### 1. Cron Job Health
Check that scheduled security jobs are running successfully:
- Run `openclaw cron list --json` and verify:
  - `nightly-security-patch` exists and has run within the last 26 hours (allows 2-hour buffer on 24h schedule)
  - Last run status is not "failed" or "timed_out"
  - If the cron is missing or has not run, report: "[HEALTH-MONITOR] ALERT: nightly-security-patch cron has not run in over 26 hours. Security skill updates may be stale."
  - If the last run timed out, report: "[HEALTH-MONITOR] WARNING: nightly-security-patch last run timed out. Check if the 120000ms timeout is sufficient for this machine."

### 2. Security Skill Loading (Dynamic — Manifest-Based)
Verify all security skills from the central repository are loaded locally:
- Fetch the current skill manifest from `https://api.github.com/repos/vamsiravuri/openclaw-security/contents/skills?ref=release`
- This manifest is the single source of truth for what skills should be installed
- Run `openclaw skills list --json` to get locally installed skills
- Compare: every skill directory in the manifest should have a corresponding locally installed skill
- For each skill in the manifest that is NOT installed locally, report: "[HEALTH-MONITOR] ALERT: Security skill '{skill_name}' from central repository is not installed locally. It may be missing YAML frontmatter or failed to download. Check ~/.openclaw/skills/{skill_name}/SKILL.md"
- Also verify Clawdex is installed: check for `clawdex` in the local skills list. If missing, report: "[HEALTH-MONITOR] WARNING: Clawdex (malicious skill scanner) is not installed. Run: openclaw skills install clawdex"

Do NOT hardcode the expected skill list. Always derive it from the GitHub manifest so this check stays correct as new skills are added.

### 3. Gateway Status
Check the OpenClaw gateway is running and responsive:
- Verify the gateway process is active
- Check that it is bound to loopback (127.0.0.1) — if bound to 0.0.0.0 or a public interface, report: "[HEALTH-MONITOR] ALERT: Gateway is not bound to loopback. This exposes the agent to network access. Run: openclaw gateway --force with loopback binding."

### 4. OpenClaw Version and Security Patch Status
Check the installed OpenClaw version against known security patch milestones:
- Run `openclaw --version` and report the version

Apply the following version-based security patch assessment. Each entry represents a version that patched one or more known vulnerabilities. If the installed version is older than the listed version, the associated CVEs are UNPATCHED on this machine.

**CRITICAL — Active exploitation risk, patch immediately:**

- Version < 2026.1.29 — CVE-2026-25253 (CVSS 8.8): One-click RCE via token exfiltration through Control UI. Attacker crafts a malicious link; victim clicks it; attacker gains full gateway control, can disable sandbox, and execute arbitrary code. Exploitable even on loopback-bound instances.
  Report: "[HEALTH-MONITOR] CRITICAL: OpenClaw version {version} is missing the patch for CVE-2026-25253 (one-click RCE, CVSS 8.8). Update to 2026.1.29 or later IMMEDIATELY. Run: npm install -g openclaw@latest"

- Version < 2026.2.2 — SSRF in media attachment handling. Gateway fetches attacker-supplied URLs targeting internal services, cloud metadata (169.254.169.254), and localhost endpoints. Enables internal network reconnaissance and data exfiltration via attachments.
  Report: "[HEALTH-MONITOR] CRITICAL: OpenClaw version {version} is missing the SSRF media handling patch (fixed in 2026.2.2). Internal network and cloud metadata endpoints are reachable via crafted media URLs. Update immediately."

- Version < 2026.2.13 — Log poisoning via unsanitized WebSocket headers. Attackers inject up to 15KB of structured prompt injection payloads into gateway logs through Origin and User-Agent headers. When the agent reads logs for debugging, injected content enters the reasoning context.
  Report: "[HEALTH-MONITOR] CRITICAL: OpenClaw version {version} is missing the log poisoning patch (fixed in 2026.2.13). Gateway logs can be poisoned with prompt injection payloads via WebSocket headers. Update immediately."

- Version < 2026.2.14 — CVE-2026-26322 (CVSS 7.6): SSRF via Gateway tool gatewayUrl parameter. Allows outbound WebSocket connections to arbitrary targets including internal services and cloud metadata. Also fixes CVE-2026-26319 (missing Telnyx webhook auth, CVSS 7.5), CVE-2026-26329 (path traversal in browser upload), CVE-2026-26326 (skills.status secret disclosure), and two additional SSRF vulnerabilities in image tool and Urbit auth.
  Report: "[HEALTH-MONITOR] CRITICAL: OpenClaw version {version} is missing patches for 6 CVEs disclosed by Endor Labs (fixed in 2026.2.14), including CVE-2026-26322 (Gateway SSRF, CVSS 7.6) and CVE-2026-26319 (webhook auth bypass, CVSS 7.5). Update immediately."

**HIGH — Security hardening, update within 24 hours:**

- Version < 2026.2.23 — Security hardening release: browser SSRF policy defaults to trusted-network mode, HSTS headers added, session cleanup hardened against storage overflow and data leaks, exec approval binding to exact argv identity (prevents trailing-space executable path swaps), symlink escape protections in browser temp paths and exec CWD, Signal/Discord reaction event authorization enforcement, credential redaction improvements.
  Report: "[HEALTH-MONITOR] HIGH: OpenClaw version {version} is missing the 2026.2.23 security hardening release. This includes SSRF policy defaults, exec approval hardening, and symlink protections. Update within 24 hours. Run: npm install -g openclaw@latest"

- Version < 2026.2.25 — IPv6 multicast SSRF blocking (ff00::/8), Microsoft Teams file consent authorization binding, Anthropic subscription auth hardened to setup-token-only, additional exec approval argv whitespace fixes, browser upload path revalidation at use-time.
  Report: "[HEALTH-MONITOR] HIGH: OpenClaw version {version} is missing the 2026.2.25 security fixes including IPv6 multicast SSRF blocking and Teams file consent hardening. Update within 24 hours."

**Reporting format for version check:**

```
VERSION STATUS:
  Installed: {version}
  Minimum safe version: 2026.2.25
  Patch status: {UP TO DATE / CRITICAL — {count} unpatched CVEs / HIGH — missing hardening}
  Unpatched CVEs: {list of CVE IDs and descriptions, or "none"}
  Action required: {specific update command or "none"}
```

If the version is current (>= 2026.2.25), report: "[HEALTH-MONITOR] OK: OpenClaw version {version} is up to date with all known security patches."

**Important**: This check reports only. It does NOT automatically update OpenClaw. Updates require human action because they may include breaking changes (such as the browser SSRF policy change in 2026.2.23 which requires running `openclaw doctor --fix` to migrate). After updating, operators must restart the gateway: `openclaw gateway --force`

### 5. Security Skill Content Drift
Check if locally installed skill content matches the latest from the central repository:
- For each skill in the GitHub manifest, compare the local SKILL.md content hash with the remote content
- If any local skill differs from the remote version, report: "[HEALTH-MONITOR] WARNING: Skill '{skill_name}' content differs from central repository. The nightly cron should have updated it. Possible causes: cron failure, GitHub CDN caching (wait 60 seconds after push), or local manual edit."
- This check catches the scenario where a skill file was manually edited locally and diverged from the central source of truth

### 6. Disk and Resource Check
Basic resource monitoring:
- Check available disk space. If less than 1GB free, report: "[HEALTH-MONITOR] WARNING: Low disk space ({available}). This may prevent skill updates and log storage."
- Check if the OpenClaw skills directory exists and is writable

## Report Format

Produce a structured health report:

```
=== HEALTH MONITOR REPORT ===
Timestamp: {timestamp}
Machine: {hostname}
OpenClaw Version: {version}

VERSION STATUS:
  Installed: {version}
  Minimum safe version: 2026.2.25
  Patch status: {UP TO DATE / CRITICAL / HIGH}
  Unpatched CVEs: {list or "none"}
  Action required: {command or "none"}

CRON STATUS:
  nightly-security-patch: {OK/ALERT/WARNING} — Last run: {timestamp}, Status: {status}

SKILL LOADING:
  Skills in central manifest: {count}
  Skills installed locally: {count}
  Missing from local: {list or "none"}
  Clawdex: {installed/missing}

GATEWAY:
  Status: {running/stopped}
  Binding: {127.0.0.1/other}

CONTENT DRIFT:
  Skills out of sync: {list or "none"}

RESOURCES:
  Disk space: {available}

CRITICAL: {count}
ALERTS: {count}
WARNINGS: {count}
==============================
```

## Severity Classification

- **CRITICAL**: Requires immediate action — unpatched CVEs with known exploits, active exploitation risk. The operator must update OpenClaw before continuing normal use.
- **ALERT**: Requires urgent attention — missing cron, missing skills that are in the manifest, gateway exposed to non-loopback interface
- **HIGH**: Should be addressed within 24 hours — missing security hardening releases
- **WARNING**: Should be addressed soon — content drift, low disk space, timeout issues, missing Clawdex
- **OK**: Healthy — all checks passed

## Integration Notes

- This skill should be included in the nightly-security-patch cron steps. Add a health check step after the skill update and audit steps.
- This skill is cross-platform compatible (WSL, Mac, Raspberry Pi). The 120000ms cron timeout is specifically set to accommodate low-power devices like Raspberry Pi.
- If this skill detects that the nightly cron itself is broken, it cannot self-repair (a broken cron cannot fix itself). In this case, the user must manually run the bootstrap: `curl -s https://raw.githubusercontent.com/vamsiravuri/openclaw-security/release/setup.sh | bash`
- The GitHub API call in check #2 uses the same URL pattern already whitelisted in prompt-injection-detector's trusted sources for the vamsiravuri/openclaw-security repository.
- On first deployment, if this skill is pulled before other new skills in the same batch, the manifest check will correctly show those other skills as "missing from local." This resolves on the next cron cycle once all skills are downloaded. This is expected behavior, not a bug.
- The version-vs-patch database in check #4 will need to be updated as new CVEs are disclosed. This is part of ongoing security skill maintenance — when new OpenClaw CVEs are published, update this skill with the new version thresholds and push to the repo. The nightly cron will propagate the update to all machines.
- The minimum safe version (currently 2026.2.25) should be updated whenever a new security-relevant OpenClaw release is published. This ensures all machines across the fleet are held to the same patch standard.
