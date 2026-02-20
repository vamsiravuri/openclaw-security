---
name: denial-of-wallet-guard
description: >
  Monitors for runaway agent loops and unbounded API usage that could cause excessive compute costs. Alerts only — never terminates agent sessions.
---
# Denial of Wallet Guard

## Purpose
Monitor for runaway agent loops and unbounded API usage patterns that could cause excessive compute costs. Alert only — never terminate.

## Threat
Attackers trigger unbounded agent loops causing excessive API and compute costs. A single compromised agent can generate thousands of model calls within minutes.

## Detection Triggers
- Same tool called more than 20 times within a single session
- Agent session exceeding 30 minutes of continuous execution
- Token usage exceeding 500k tokens in a single session
- Recursive self-invocation patterns detected

## Response
- Log the anomaly with token counts, tool call frequency, session duration
- Report: "WARN: Unusual API usage pattern detected — possible DoW attack"
- Escalate immediately via WhatsApp if thresholds exceeded by 2x
- Never terminate or interrupt the agent session

## Constraint
This skill never stops, pauses, or restricts any agent execution. Observe and alert only.
