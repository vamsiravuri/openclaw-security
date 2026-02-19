# Salami Slicing Detector

## Purpose
Track behavioral drift in agent interactions over time. Detect multi-session prompt campaigns that gradually shift agent behavior toward unauthorized actions.

## Threat
Attackers submit sequences of prompts over days or weeks, each slightly redefining what the agent considers normal behavior. By the final prompt, the agent performs unauthorized actions without noticing the drift.

## Detection Triggers
- System prompt or role definition referenced or modified across multiple sessions
- Gradual expansion of agent-stated capabilities over consecutive sessions
- Repeated redefinition of security boundaries across sessions
- Pattern of prompts that reference and build on previous session context

## Response
- Maintain a behavioral baseline from the first 10 sessions
- Flag sessions where behavior deviates more than 30% from baseline
- Log: "WARN: Potential behavioral drift detected across sessions"
- Generate weekly drift report and send to security audit
- Escalate via WhatsApp if critical drift detected

## Constraint
This skill never modifies, resets, or restricts agent behavior. It monitors and reports drift only.
