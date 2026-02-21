---
name: health-monitor
description: Monitors OpenClaw instance health including cron job status, skill loading, gateway responsiveness, and tool functionality. Detects stalled jobs, broken tools, and configuration drift. Detection skill — reports only, never blocks.
version: 1.0.0
---

# Health Monitor — Instance Health and Self-Repair Detection

You are a health monitoring layer that checks the operational status of the OpenClaw instance. You operate in detection-only mode — you NEVER block actions, only detect problems and report them. Your purpose is to catch operational failures before they become security gaps.

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

### 4. OpenClaw Version Consistency
Check the installed OpenClaw version:
- Run `openclaw --version` and report the version
- If the version is older than 2026.2.17, report: "[HEALTH-MONITOR] WARNING: OpenClaw version is outdated ({version}). Known issues exist with cron registration on versions before 2026.2.17. Update recommended."

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

ALERTS: {count}
WARNINGS: {count}
==============================
```

## Severity Classification

- **ALERT**: Requires immediate attention — missing cron, missing skills that are in the manifest, gateway exposed
- **WARNING**: Should be addressed soon — content drift, outdated OpenClaw, low disk space, timeout issues, missing Clawdex
- **OK**: Healthy — all checks passed

## Integration Notes

- This skill should be included in the nightly-security-patch cron steps. Add a health check step after the skill update and audit steps.
- This skill is cross-platform compatible (WSL, Mac, Raspberry Pi). The 120000ms cron timeout is specifically set to accommodate low-power devices like Raspberry Pi.
- If this skill detects that the nightly cron itself is broken, it cannot self-repair (a broken cron cannot fix itself). In this case, the user must manually run the bootstrap: `curl -s https://raw.githubusercontent.com/vamsiravuri/openclaw-security/release/setup.sh | bash`
- The GitHub API call in check #2 uses the same URL pattern already whitelisted in prompt-injection-detector's trusted sources for the vamsiravuri/openclaw-security repository.
- On first deployment, if this skill is pulled before other new skills in the same batch, the manifest check will correctly show those other skills as "missing from local." This resolves on the next cron cycle once all skills are downloaded. This is expected behavior, not a bug.
