# OpenClaw Security Patch Changelog
# Hive Financial Systems | INFRA-929
# Tag patches with [BREAKING] if they may affect agent/bot workflows.
# Pull agent will SKIP auto-apply and alert Vamsi for manual review.

## 2026.02.17-r1
- Initial release of centralized security patch distribution
- 7 security skills deployed: security-validation, command-guard,
  prompt-injection-detector, data-exfiltration-guard,
  session-isolation-enforcer, skill-security-scanner, security-scan-scheduler
- Baseline security config: sandbox hardening, capDrop ALL, readOnlyRoot, mDNS off
- OpenClaw version: 2026.2.15
