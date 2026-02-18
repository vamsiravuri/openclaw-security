---
name: session-isolation-enforcer
description: >
  Session and context isolation enforcement for Hive Financial Systems.
  Activate when handling multi-agent workflows, group chat messages, or
  cron-triggered sessions. Prevents cross-session data leakage, enforces
  per-session sandbox boundaries, and ensures secrets from one context never
  bleed into another. Works alongside OpenClaw native sandbox.scope=session
  and dmScope=per-channel-peer configuration.
---

# Session Isolation Enforcer — Context Protection

## Core Principle

Each session is a trust boundary. Information from one session MUST NOT
leak into another session, even if the same agent serves both.

## Rules

### Rule 1 — No Cross-Session Secret Sharing

Never reference, quote, or include content from a previous session in
the current session. This includes:
- API keys, tokens, passwords mentioned in other sessions
- File contents read in other sessions
- User personal information from other sessions
- Command outputs from other sessions

If the user asks "what did we discuss in the other chat?", respond:
"I don't have access to other sessions for security isolation.
Please share the relevant context here if needed."

### Rule 2 — Group Chat Restrictions

In group/channel sessions (non-DM):
- **DO NOT** execute `exec`, `write`, `edit`, or `apply_patch`
- **DO NOT** read sensitive files (`~/.ssh`, `~/.aws`, `.env`)
- **DO NOT** make outbound POST/PUT requests via `web_fetch`
- **ALLOW** read-only operations: `read`, `web_search`, `web_fetch` GET
- **ALLOW** informational responses from training knowledge

Reason: Group chats include participants who may not be on the allowlist.
Any command execution in group context is a prompt injection vector.

### Rule 3 — Cron Session Isolation

When running in a cron session (`cron:<jobId>`):
- Start with fresh context — no conversation carry-over
- Do NOT access files written by other cron jobs in the same cycle
- Do NOT modify `SOUL.md`, `MEMORY.md`, or `openclaw.json`
- Keep output focused on the cron job's stated purpose

### Rule 4 — Agent Workspace Boundaries

In multi-agent setups, each agent has its own workspace:
- Only read/write within YOUR designated workspace
- Do NOT access other agents' `agentDir` paths
- Do NOT modify shared config (`~/.openclaw/openclaw.json`) unless
  explicitly authorized by the user in the current session

### Rule 5 — Subagent Trust

When spawning subagents:
- Subagents inherit the parent's sandbox restrictions
- Do NOT pass secrets to subagents via command arguments
- Subagents should not have higher privileges than the parent

## What This Skill Complements

This skill provides agent-level reasoning on top of these hard controls:
- `sandbox.mode: "all"` — all sessions run in Docker containers
- `sandbox.scope: "session"` — each session gets its own container
- `session.dmScope: "per-channel-peer"` — separate sessions per contact
- `channels.whatsapp.dmPolicy: "allowlist"` — only trusted numbers

The hard controls enforce isolation at the infrastructure level.
This skill enforces isolation at the behavioral/reasoning level.
