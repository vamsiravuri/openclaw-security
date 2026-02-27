---
name: config-tamper-detector
description: Detects unauthorized changes to OpenClaw configuration including sandbox settings, tool policies, auth tokens, device auth, and permission scopes. Detection skill — reports only, never blocks.
version: 1.0.0
---

# Config Tamper Detector

## Purpose

Monitor for unauthorized or suspicious changes to OpenClaw configuration that could weaken security posture, disable safety controls, or expand attack surface. This skill provides continuous configuration integrity monitoring with drift detection from a known-good security baseline.

This skill addresses the attack chain from CVE-2026-25253 (CVSS 8.8), where an attacker who gained gateway access could modify configuration to disable sandboxing and tool safety prompts before executing arbitrary code. It also addresses the broader pattern of configuration-based attacks documented by Microsoft, CrowdStrike, Palo Alto Networks, and Conscia in February 2026, where misconfigured OpenClaw instances were the primary enabler of compromise.

## Threat Model

Configuration tampering is the pivot point between initial access and full compromise:

1. **Post-exploit config weakening**: After gaining gateway access (via token theft, SSRF, or other vectors), attackers disable sandbox mode, remove tool restrictions, and turn off safety prompts before executing malicious commands
2. **Gradual privilege escalation**: Incremental config changes that individually appear minor but cumulatively remove security controls (expanding allowlists, enabling dangerous flags, adding untrusted devices)
3. **Configuration drift**: Unintentional changes that accumulate over time and weaken the security posture relative to the hardened baseline
4. **Plugin allowlist manipulation**: Modifying `plugins.allow` to enable unauthorized extensions that bypass security controls
5. **Channel policy weakening**: Changing DM/group policies to allow unauthorized senders to interact with the agent

## Detection Rules

### 1. Critical Security Config Changes
Flag immediately when any of the following are modified:
- `sandbox` settings: mode, container capabilities, filesystem permissions, network access
- `security.approval` or exec approval settings: changes to allowlist/ask/deny policies
- `tools.deny` or `tools.allow`: modifications to tool restriction lists
- `gateway.auth`: changes to authentication requirements, device auth bypass flags
- `gateway.bind` or `gateway.host`: changes from loopback (127.0.0.1) to broader network interfaces (0.0.0.0)
- `dangerously*` prefixed configuration options: any break-glass flag being enabled
- `security.trust_model`: changes to the trust boundary configuration

### 2. Credential and Token Changes
Flag when:
- API keys or provider tokens are added, removed, or modified outside of the onboarding flow
- Gateway tokens are rotated without an explicit operator-initiated rotation command
- Device pairing tokens or auth bypass flags are modified
- OAuth scopes are expanded beyond the previously configured set
- Webhook authentication settings are disabled or weakened (relates to CVE-2026-26319)

### 3. Plugin and Skill Policy Changes
Flag when:
- `plugins.allow` list is modified to add new entries
- Skills are enabled that were not part of the managed security installation
- Skill loading paths (`skills.load.extraDirs`) are modified to include new directories
- A skill's environment variables or API key injection settings are changed

### 4. Channel and Access Policy Changes
Flag when:
- DM policy changes from restricted to open
- Group policy changes to allow broader access
- New channels are enabled without corresponding operator action
- Allowlists for message senders are expanded
- Auto-reply settings are modified to respond to previously blocked sources

### 5. Baseline Drift Detection
Maintain awareness of the expected security configuration baseline for Hive deployments:
- Sandbox mode should be enabled for non-main sessions
- Gateway should be bound to loopback only (127.0.0.1)
- Device auth should be enabled
- Tool restrictions should include at minimum the "nodes" tool on the deny list
- No `dangerously*` flags should be enabled
- Browser SSRF policy should be set to "trusted-network" (default since v2026.2.23)

When the agent observes configuration that deviates from these expectations, report the drift without modifying it.

## Response Behavior

This skill DETECTS and REPORTS only. It never blocks configuration changes or reverts settings.

When a suspicious configuration change or drift is detected:

1. Report the finding with: the specific config key changed, the previous value (if known), the new value, and which detection rule triggered
2. Classify the severity:
   - CRITICAL: sandbox disabled, auth bypass enabled, gateway exposed to non-loopback
   - HIGH: tool restrictions removed, credential changes outside onboarding, dangerously* flags enabled
   - MEDIUM: plugin allowlist expanded, channel policies broadened, new skill directories added
   - LOW: configuration drift from baseline that does not directly weaken a security control
3. For CRITICAL and HIGH findings, recommend the operator verify the change was intentional
4. Log the detection for the audit-event-logger to capture in session records

## Scope

This skill monitors configuration state during agent sessions. It does not:
- Block or revert configuration changes
- Prevent operators from making intentional configuration modifications
- Modify any configuration files or settings
- Interfere with the onboarding flow or initial setup
- Replace upstream OpenClaw security patches (ensure instances are updated to latest version)
- Conflict with the nightly security cron or any automated security workflows

## Integration Notes

Works alongside existing security skills:
- health-monitor checks overall instance health including version and skill loading
- audit-event-logger records security events including configuration changes
- session-isolation-enforcer prevents data leakage between sessions
- security-validation validates agent actions against security policy
- This skill adds focused configuration integrity monitoring that none of the above specifically cover
- The nightly security cron is a trusted source and its operations will not be flagged
