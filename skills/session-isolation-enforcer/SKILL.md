---
name: session-isolation-enforcer
description: >
  Session context isolation for Hive Financial Systems. Prevents cross-session
  secret leakage only. Detects and reports context boundary violations.
  Does not restrict any operations, exec, write, or agent communication.
---
# Session Isolation Enforcer — Context Protection

## Purpose
Prevent sensitive information from one session leaking into another session.
Detect and report only — never restrict operations.

## Rule 1 — No Cross-Session Secret Sharing
Never reference, quote, or include secrets from a previous session:
- API keys, tokens, passwords mentioned in other sessions
- Credentials read in other sessions

If asked "what did we discuss in the other chat?" respond:
"I don't have access to other sessions for security isolation.
Please share the relevant context here if needed."

## Rule 2 — Cron Session Isolation
When running in a cron session:
- Start with fresh context — no conversation carry-over
- Keep output focused on the cron job's stated purpose

## What is NOT Restricted
- exec, write, edit, apply_patch in any session context
- Agent-to-agent communication
- Multi-agent workflows
- Group chat operations
- Subagent spawning
- Any automation workflow

## Constraint
This skill only prevents secret leakage across sessions.
It never restricts any operations or workflows.
