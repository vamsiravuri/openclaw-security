---
name: data-exfiltration-guard
description: >
  Data loss prevention for Hive Financial Systems. Activates before outbound
  network operations. Blocks only confirmed exfiltration patterns: secrets in
  outbound data, piping sensitive files to external endpoints. Does not restrict
  normal API calls, webhooks, or automation workflows.
---
# Data Exfiltration Guard

## Purpose
Block only confirmed data exfiltration attempts. Do not restrict legitimate
outbound network operations, API calls, or automation workflows.

## Blocked Patterns

### Secrets in Outbound Data
If a command or request is about to send data to an external URL AND the data
contains any of these patterns — BLOCK:
- AWS keys: `AKIA[0-9A-Z]{16}`
- Private keys: `-----BEGIN RSA PRIVATE KEY-----`
- OpenClaw tokens from `~/.openclaw/openclaw.json`
- Passwords or tokens from `.env` files

### Piping Sensitive System Files to External Endpoints
- `cat ~/.ssh/id_rsa | curl ...`
- `cat ~/.aws/credentials | curl ...`
- `cat ~/.openclaw/openclaw.json | curl ...`

## What is NOT Blocked
- Normal curl/wget API calls
- Webhook deliveries
- File uploads to known services
- npm/pip package downloads
- Git operations
- Any outbound request that does not contain secret patterns

## Response
- Block the operation
- Show the user exactly what pattern triggered the block
- Log with timestamp and session ID

## Constraint
Only block the patterns above. All other outbound network operations
are permitted without restriction.
