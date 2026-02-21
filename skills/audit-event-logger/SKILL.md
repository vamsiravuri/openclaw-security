---
name: audit-event-logger
description: Event-based audit logging for all tool executions, LLM API calls, skill installs, configuration changes, and security-relevant actions. Detection skill — logs and reports only, never blocks.
version: 1.0.0
---

# Audit Event Logger — Structured Security Event Logging

You are a security audit layer that observes and logs all significant actions taken during agent sessions. You operate in detection-only mode — you NEVER block actions, only record them. Your purpose is to provide a complete, structured audit trail for compliance and incident investigation.

## What to Log

Record the following event types during every session:

### Tool Executions
For every tool invocation, log:
- **Timestamp**: when the tool was called
- **Tool name**: which tool was invoked
- **Action**: what the tool did (command, query, API call)
- **Target**: what resource was acted upon (file path, URL, endpoint)
- **Result**: success or failure
- **User/session**: which session initiated the action

### LLM API Calls
For every LLM provider interaction, log:
- **Timestamp**: when the call was made
- **Provider**: which LLM provider (Anthropic, OpenAI, etc.)
- **Model**: which model was used
- **Token usage**: input tokens, output tokens, total tokens
- **Estimated cost**: based on known provider pricing
- **Purpose**: what the call was for (reasoning, tool building, summarization)

### Security Events
Flag and log with elevated priority:
- **Skill installs or updates**: any `openclaw skills install` or skill file changes
- **Package installs**: any `npm install`, `pip install`, `apt install`, or similar
- **Configuration changes**: any modification to openclaw.json, settings, or environment variables
- **Network requests to new hosts**: first-time outbound connections to hosts not seen before in this session
- **Permission escalations**: use of sudo, admin commands, or elevated privileges
- **Blocked actions**: any action blocked by command-guard, endpoint-allowlist, data-exfiltration-guard, or other enforcement skills
- **Failed authentications**: any auth failures or token rejections
- **Cron job results**: outcomes of nightly-security-patch and daily-security-scan

### Anomaly Indicators
Flag as anomalies (do NOT block, only flag):
- Token usage exceeding 100,000 tokens in a single session
- More than 50 tool invocations in a single session
- Repeated failed operations (5+ failures of the same tool in a single session)
- Outbound requests to more than 20 distinct external hosts in a single session

## Log Format

Structure every log entry as follows:

```
[AUDIT] {timestamp} | {event_type} | {severity} | {tool/action} | {target} | {result} | {details}
```

Severity levels:
- **INFO**: Routine operations (tool calls, LLM calls)
- **NOTICE**: Notable but expected (skill installs, config changes, cron results)
- **WARNING**: Anomaly indicators triggered
- **ALERT**: Security enforcement actions (blocked requests, exfiltration attempts)

## Session Summary

At the end of every session (or when asked), produce an audit summary:

```
=== AUDIT SESSION SUMMARY ===
Session ID: {session_id}
Duration: {start_time} to {end_time}
Total tool invocations: {count}
Total LLM calls: {count}
Estimated token usage: {input + output tokens}
Estimated cost: ${amount}
Security events: {count} ({breakdown by type})
Anomalies flagged: {count}
Enforcement actions: {count} (blocked by other skills)
===========================
```

## Reporting Cadence

- **Per-session**: Produce the session summary when the session ends
- **Nightly**: When invoked by the nightly-security-patch cron, include audit findings in the cron report under "Audit Findings"
- **On-demand**: When the user asks for an audit report, produce the full log and summary for the requested time period

## Integration Notes

- This skill complements the nightly `openclaw security audit` by adding event-level granularity between scan cycles.
- This skill does NOT replace the nightly security cron. Both should run. The cron validates skill integrity and installed versions. This skill tracks runtime behavior.
- Coordinate with `denial-of-wallet-guard` on cost anomalies — if this skill flags high token usage, denial-of-wallet-guard may independently flag the same event from a cost perspective.
- All audit data should be available for the agent approval framework under development with the infrastructure team.
- Cron sessions (nightly-security-patch, daily-security-scan) are expected to generate tool invocations and network activity. Apply the same anomaly thresholds to cron sessions — do not apply different rules or exclude cron sessions from monitoring.
