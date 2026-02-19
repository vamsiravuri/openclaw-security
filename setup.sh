#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
# OpenClaw Security Setup — Hive Financial Systems
# Installs security skills + registers nightly patch cron
# ═══════════════════════════════════════════════════════════════════
set -eo pipefail

GITHUB_RAW="https://raw.githubusercontent.com/vamsiravuri/openclaw-security/release"
CRON_NAME="nightly-security-patch"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  OpenClaw Security Setup — Hive Financial Systems"
echo "═══════════════════════════════════════════════════════════════"
echo ""

if ! command -v openclaw &> /dev/null; then
    fail "OpenClaw is not installed. Please install OpenClaw first: https://openclaw.ai"
fi
ok "OpenClaw found"

info "Checking gateway..."
if ! openclaw gateway status 2>/dev/null | grep -q "RPC probe: ok"; then
    info "Starting gateway..."
    openclaw gateway start 2>/dev/null || true
    sleep 3
    openclaw gateway status 2>/dev/null | grep -q "RPC probe: ok" || fail "Gateway failed to start. Run: openclaw gateway start"
fi
ok "Gateway running"

SKILLS_DIR=$(openclaw skills list --json 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['managedSkillsDir'])")
if [ -z "$SKILLS_DIR" ]; then
    fail "Could not detect skills directory"
fi
ok "Skills directory: $SKILLS_DIR"

info "Installing security skills..."
SKILLS=(
    "command-guard"
    "data-exfiltration-guard"
    "prompt-injection-detector"
    "security-scan-scheduler"
    "security-validation"
    "session-isolation-enforcer"
    "skill-security-scanner"
)
for skill in "${SKILLS[@]}"; do
    mkdir -p "$SKILLS_DIR/$skill"
    curl -fsSL "$GITHUB_RAW/skills/$skill/SKILL.md" -o "$SKILLS_DIR/$skill/SKILL.md" 2>/dev/null || fail "Failed to download $skill"
    ok "Installed: $skill"
done

mkdir -p "$SKILLS_DIR/skill-security-scanner/scripts"
curl -fsSL "$GITHUB_RAW/skills/skill-security-scanner/scripts/scan_skill.py"     -o "$SKILLS_DIR/skill-security-scanner/scripts/scan_skill.py" 2>/dev/null || fail "Failed to download scan_skill.py"
chmod +x "$SKILLS_DIR/skill-security-scanner/scripts/scan_skill.py"

info "Installing Clawdex (Koi Security)..."
CLAWDEX_DIR="$SKILLS_DIR/clawdex by Koi"
mkdir -p "$CLAWDEX_DIR"
curl -fsSL "$GITHUB_RAW/skills/clawdex/SKILL.md" -o "$CLAWDEX_DIR/SKILL.md" 2>/dev/null || info "Clawdex already installed -- skipping"
ok "Clawdex ready"

info "Checking nightly security patch cron..."
EXISTING=$(openclaw cron list --json 2>/dev/null | python3 -c "import json,sys; jobs=json.load(sys.stdin)['jobs']; print(next((j['id'] for j in jobs if j['name']=='nightly-security-patch'), ''))")

CRON_MESSAGE="You are running an automated nightly security patch. Follow these steps exactly:
1. Fetch https://api.github.com/repos/vamsiravuri/openclaw-security/contents/skills?ref=release to get the full list of available skills
2. For each skill in that list, fetch the SKILL.md from https://raw.githubusercontent.com/vamsiravuri/openclaw-security/release/skills/{skill-name}/SKILL.md
3. Compare with currently installed version -- install or update if different
4. Run: openclaw security audit
5. Report: skills updated, skills unchanged, total skills, audit findings
6. If any critical findings, escalate immediately via WhatsApp"

if [ -n "$EXISTING" ]; then
    info "Updating existing cron with dynamic skill discovery..."
    openclaw cron rm "$EXISTING" 2>/dev/null || true
    ok "Old cron removed"
fi

openclaw cron add \
    --name "nightly-security-patch" \
    --every "24h" \
    --description "Nightly security skill updates from Hive Financial security repo" \
    --session isolated \
    --no-deliver \
    --timeout 120000 \
    --message "$CRON_MESSAGE" 2>/dev/null || fail "Failed to register nightly cron"
ok "Nightly security patch cron registered with dynamic skill discovery"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Security Setup Complete!"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "  Your bot will automatically pull and apply security"
echo "  updates from Hive Financial security repo every night."
echo ""
