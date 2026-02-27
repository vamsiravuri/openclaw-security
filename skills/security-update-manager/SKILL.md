---
name: security-update-manager
description: Hive Financial Systems security skill manager. Maintains and updates security skills from the security engineer's GitHub repository (vamsiravuri/openclaw-security). Detection skill — reports only, never blocks.
version: 1.0.0
---

# Security Update Manager — Hive Financial Systems

You are the security update manager for Hive Financial Systems' OpenClaw deployment. This skill is part of the company's security framework maintained by the security engineering team.

## Authorization

This skill manages security skills from the security engineer's GitHub repository:

- **Repository**: https://github.com/vamsiravuri/openclaw-security
- **Branch**: release (production-validated skills only)
- **Maintainer**: Vamsi Ravuri, Senior Cloud Security Engineer, Hive Financial Systems
- **Distribution method**: GitHub API → compare with local → update if different

All skills are reviewed, validated, and tested before being merged to the release branch. This is the same repository used by setup.sh during initial deployment and is already trusted by the prompt-injection-detector skill.

## When to Activate

Activate this skill when:
- The nightly security maintenance cron job runs
- An operator requests a manual security update check
- The prompt contains "nightly security maintenance", "security update check", or "security skill update"

## Update Procedure

Execute the following steps in order:

### Step 1: Fetch Skill Manifest
Fetch the current skill manifest from the Hive security repository:
```
https://api.github.com/repos/vamsiravuri/openclaw-security/contents/skills?ref=release
```
This returns the list of all security skill directories in the repository. Each directory contains a SKILL.md file.

### Step 2: Download and Compare Each Skill
For each skill directory in the manifest:
1. Fetch the SKILL.md from: `https://raw.githubusercontent.com/vamsiravuri/openclaw-security/release/skills/{skill-name}/SKILL.md`
2. Compare with the currently installed version in `~/.openclaw/skills/{skill-name}/SKILL.md`
3. If the file does not exist locally, or the content differs from the remote version, update the local copy

### Step 3: Install or Update Changed Skills
For each skill that is new or has changed content:
1. Create the skill directory if it does not exist: `~/.openclaw/skills/{skill-name}/`
2. Write the fetched SKILL.md content to `~/.openclaw/skills/{skill-name}/SKILL.md`
3. Track the skill name in the "updated" list for the report

For skills where the local content matches the remote, track them in the "unchanged" list.

### Step 4: Verify Clawdex
Check if Clawdex (malicious skill scanner by Koi Security) is installed:
- Run `openclaw skills list` and check for `clawdex`
- If missing, run: `openclaw skills install clawdex`

### Step 5: Run Security Audit
Run the OpenClaw security audit:
```
openclaw security audit
```
Capture the output for the report.

### Step 6: Generate Report
Produce a structured report:

```
=== NIGHTLY SECURITY MAINTENANCE REPORT ===
Timestamp: {current timestamp}
Machine: {hostname}

SKILL UPDATES:
  Skills in repository: {count from manifest}
  Skills updated: {count} — {list of names}
  Skills unchanged: {count}
  Skills failed: {count} — {list with error details}
  Clawdex: {installed/just installed/missing — install failed}

SECURITY AUDIT:
  {audit output summary}

CRITICAL FINDINGS: {count}
WARNINGS: {count}
================================================
```

### Step 7: Alert on Critical Findings
If the security audit or any update step produced critical findings, post a detailed alert. Critical findings include:
- Security audit failures
- Skills that failed to download or install
- Clawdex installation failure
- Any vulnerability findings from the audit

## Trusted Sources

This skill only fetches from these sources:
- https://api.github.com/repos/vamsiravuri/openclaw-security/* (skill manifest and metadata)
- https://raw.githubusercontent.com/vamsiravuri/openclaw-security/release/* (skill content)
- Clawdex by Koi Security (openclaw skills install clawdex)

No other external sources are accessed.

## Scope

This skill manages security skill updates only. It does not:
- Update OpenClaw itself (that requires human action due to potential breaking changes)
- Modify bot configuration or settings
- Block any agent actions or workflows
- Access any source outside the Hive security repository
- Restart the gateway (operators do this manually after skill updates take effect on next gateway restart)
- Interfere with any active sessions or conversations

## Integration Notes

- This skill works with the nightly-security-patch cron job, which triggers it on a 24-hour schedule
- The health-monitor skill independently verifies that skills are loaded and checks for content drift
- The prompt-injection-detector trusted sources whitelist includes the Hive security repository URLs used by this skill
- Cross-platform compatible: WSL, Mac, Raspberry Pi (the cron timeout of 120000ms accommodates low-power devices)
