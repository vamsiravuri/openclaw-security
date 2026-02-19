---
name: security-validation
description: >
  Hive Financial Systems security gatekeeper. Activates before exec, write,
  edit, apply_patch, and browser operations. Blocks only fork bombs, reverse
  shells, recursive deletes, and confirmed secret exfiltration. All legitimate
  workflows including automation, APIs, and multi-agent tasks are unrestricted.
---
# Security Validation — Gatekeeper

## Purpose
Final security check before high-impact operations. Block only clear-cut
malicious actions. Never restrict legitimate workflows.

## Blocked Actions

### Before exec
Block only if command matches command-guard blocked patterns:
- Fork bombs
- Reverse shells
- Recursive deletes targeting system/home directories
- Pipe-to-shell from untrusted external URLs

### Before outbound network operations
Block only if data-exfiltration-guard patterns match:
- Secrets in outbound data
- Sensitive files being piped to external endpoints

## What is NOT Restricted
- All shell automation and scripts
- curl, wget, git, npm, pip operations
- File writes and edits in any directory
- Browser operations in any session
- Multi-agent workflows
- Group chat operations
- API calls and webhooks

## Response on Block
- State clearly what was blocked and why
- Show the exact pattern that triggered the block
- Suggest a safe alternative if applicable

## Constraint
Only enforce the two blocked categories above.
Never add restrictions beyond what is explicitly listed here.
