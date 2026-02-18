---
name: security-scan-scheduler
description: >
  Autonomous security scan scheduler for Hive Financial Systems. Activate
  when triggered by a cron job or when the user requests a security scan.
  Performs threat intelligence gathering via web_search, scans installed
  skills for malicious patterns, audits OpenClaw configuration for security
  gaps, and reports findings with CVSS-based risk tiering. Escalates
  critical findings to the user via WhatsApp. This is the ASA (Autonomous
  Security Agent) reimplemented as an OpenClaw-native skill.
---

# Security Scan Scheduler — Autonomous Security Agent

## When This Skill Activates

1. **Cron-triggered:** When OpenClaw's cron system sends the daily security
   scan message (configured during installation)
2. **User-requested:** When the user says "run a security scan" or similar

## Scan Cycle (run all steps in order)

### Phase 1 — Threat Intelligence (use web_search)

Search for recent threats using these queries (one at a time):
1. `"OpenClaw vulnerability CVE 2026"`
2. `"OpenClaw security exploit"`
3. `"ClawHub malicious skills"`

For each search result:
- Extract: title, source URL, severity keywords (critical/high/medium/low)
- Estimate CVSS score based on impact:
  - RCE (remote code execution) → 8.5-10.0
  - Data exfiltration → 7.0-8.5
  - Information disclosure → 4.0-7.0
  - Denial of service → 3.0-5.0
- Record: `{title, url, estimated_cvss, date}`

### Phase 2 — Installed Skills Audit

Run the skill security scanner on all installed skills:
```bash
python3 ~/.openclaw/skills/skill-security-scanner/scripts/scan_skill.py scan-all
```

Review the JSON output:
- BLOCKED skills → **CRITICAL** finding, recommend immediate removal
- WARNING skills → note for human review
- CLEAN skills → no action needed

### Phase 3 — Configuration Audit

Check the current OpenClaw configuration for security gaps. Read
`~/.openclaw/openclaw.json` and verify:

| Setting | Expected Value | Risk if Missing |
|---------|---------------|-----------------|
| `agents.defaults.sandbox.mode` | `"all"` | Main session runs on host |
| `agents.defaults.sandbox.scope` | `"session"` | Cross-session bleed |
| `agents.defaults.sandbox.docker.network` | `"none"` | Network exfiltration from sandbox |
| `tools.elevated.enabled` | `false` | Host escape hatch open |
| `tools.deny` | includes `"browser"` | Unrestricted browser access |
| `discovery.mdns.mode` | `"off"` | Network presence broadcast |
| `gateway.controlUi.dangerouslyDisableDeviceAuth` | `false` | Unauthenticated UI access |
| `gateway.bind` | `"loopback"` | Remote gateway access |

Flag any missing or incorrect settings.

### Phase 4 — Risk Assessment & Report

Compile findings into a report:

```
═══════════════════════════════════════════
  SECURITY SCAN REPORT — [date]
═══════════════════════════════════════════

THREAT INTELLIGENCE:
  [N] new threats found
  [list with CVSS scores]

SKILL AUDIT:
  [N] skills scanned
  [N] clean / [N] warnings / [N] blocked

CONFIG AUDIT:
  [N] settings checked
  [N] compliant / [N] gaps found

RISK SUMMARY:
  CRITICAL: [count] — immediate action required
  HIGH:     [count] — action within 24 hours
  MEDIUM:   [count] — action within 1 week
  LOW:      [count] — informational
═══════════════════════════════════════════
```

### Phase 5 — Escalation

**CVSS ≥ 9.0 (Critical):** Send alert to user immediately.
**CVSS 7.0-8.9 (High):** Include in daily report, flag for review.
**CVSS 4.0-6.9 (Medium):** Include in weekly summary.
**CVSS < 4.0 (Low):** Log only, no alert.

Do NOT auto-deploy fixes. All remediations require human approval.
This is a detection and alerting system, not an auto-remediation system.

## Important Limitations

- Web search results may contain false positives — verify before acting
- CVSS estimates are approximate — official NVD scores take precedence
- This is defense-in-depth — hard enforcement comes from sandbox + tool policy
- The scan runs in an isolated cron session — it cannot modify main config
