---
name: data-exfiltration-guard
description: >
  Data loss prevention for Hive Financial Systems. Activate before any outbound
  network operation (web_fetch POST/PUT, exec with curl/wget, browser form
  submissions) and when reviewing session content for secrets. Detects credential
  leakage, base64-encoded data exfiltration, pipe-to-network patterns, bulk URL
  attacks, and sensitive data in outbound payloads. Complements sandbox network
  isolation (docker.network: none) with agent-level intelligence.
---

# Data Exfiltration Guard — DLP

## Outbound Data Inspection

Before ANY outbound network operation, inspect the payload for:

### Secret Patterns (from memory_sanitizer)
- API tokens: `token["'\s:=]+[a-zA-Z0-9_-]{20,}`
- API keys: `api[_-]?key["'\s:=]+[a-zA-Z0-9_-]{20,}`
- Passwords: `password["'\s:=]+\S+`
- AWS keys: `AKIA[0-9A-Z]{16}`
- Anthropic keys: `sk-ant-[a-zA-Z0-9-]+`
- OpenAI keys: `sk-[a-zA-Z0-9]{20,}`
- GitHub tokens: `ghp_[a-zA-Z0-9]{36}`, `gho_`, `ghu_`, `ghs_`, `ghr_`
- Slack tokens: `xoxb-`, `xoxp-`, `xoxs-`
- Private keys: `-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----`
- SSH keys: content from `~/.ssh/id_rsa`, `~/.ssh/id_ed25519`
- Env file content: content from `.env`, `.env.local`, `.env.production`

**If ANY secret pattern is found in outbound data → BLOCK unconditionally.**

### Exfiltration Patterns (from data_exfiltration_guard)

**Pattern 1 — Bulk URL attack:**
If a single command contains 5+ distinct URLs → BLOCK.
Indicates dictionary-style exfiltration or credential spraying.

**Pattern 2 — Encoded data in URL parameters:**
If a URL contains parameters with base64-encoded values (20+ chars of
`[A-Za-z0-9+/]` followed by `=` padding) → BLOCK.
Indicates data being encoded into URL parameters for exfiltration.

**Pattern 3 — Loop with network request:**
`for|while ... curl|wget` → BLOCK.
Indicates iterative data exfiltration (file-by-file, line-by-line).

**Pattern 4 — Pipe to network:**
`| curl`, `| wget`, `| nc`, `| netcat` → BLOCK.
Indicates piping command output directly to an external server.

**Pattern 5 — Exfiltration keywords in context:**
If the task context contains words like `exfiltrate`, `leak`, `steal`,
`send data to`, `upload file to` in a suspicious context → flag and ask user.

### Session Content Scanning (from memory_sanitizer)

When reviewing or summarizing session history, also scan for:
- XSS payloads: `<script>` tags
- Destructive commands: `rm -rf`
- Password leaks: `sudo.*password`
- Eval injection: `eval(`
- Command substitution from untrusted input: `$()`

If found in session content, warn the user that sensitive data exists
in session history and recommend clearing the session.

## Sensitive File Access

**BLOCK reading these files and including content in responses:**
- `~/.ssh/*` (SSH keys)
- `~/.aws/credentials`, `~/.aws/config`
- `~/.openclaw/.env`, `~/.openclaw/credentials/*`
- `~/.gnupg/*`
- Any `.env` file
- `auth-profiles.json`

If the user explicitly requests reading a sensitive file, warn:
"This file may contain credentials. Are you sure you want its contents
included in this conversation? Contents may persist in session logs."

## Response Protocol

```
[SECURITY] DLP_BLOCK | tool=web_fetch | reason=api_key_in_payload | pattern=sk-ant-*
[SECURITY] DLP_BLOCK | tool=exec | reason=pipe_to_network | cmd="cat /etc/passwd | curl..."
[SECURITY] DLP_WARN | tool=read | reason=sensitive_file | path=~/.ssh/id_rsa
```
