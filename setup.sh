#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
# OpenClaw Security Setup — Hive Financial Systems
# Dynamically installs security skills + registers nightly cron
# Version: 2.0.0 — Feb 27, 2026
# ═══════════════════════════════════════════════════════════════════
set -eo pipefail

GITHUB_API="https://api.github.com/repos/vamsiravuri/openclaw-security/contents/skills?ref=release"
GITHUB_RAW="https://raw.githubusercontent.com/vamsiravuri/openclaw-security/release"
CRON_NAME="nightly-security-patch"
MIN_VERSION="2026.2.25"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  OpenClaw Security Setup — Hive Financial Systems"
echo "  Maintained by: Vamsi Ravuri, Security Engineering"
echo "  Repo: github.com/vamsiravuri/openclaw-security"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# --- Pre-flight checks ---

if ! command -v openclaw &> /dev/null; then
    fail "OpenClaw is not installed. Install first: https://openclaw.ai"
fi
ok "OpenClaw found"

CURRENT_VERSION=$(openclaw --version 2>/dev/null || echo "unknown")
ok "Version: $CURRENT_VERSION"

if [ "$CURRENT_VERSION" != "unknown" ]; then
    if [ "$(printf '%s\n' "$MIN_VERSION" "$CURRENT_VERSION" | sort -V | head -n1)" != "$MIN_VERSION" ]; then
        warn "OpenClaw $CURRENT_VERSION is below minimum safe version $MIN_VERSION"
        warn "Critical security patches are missing. Update: npm install -g openclaw@latest"
        warn "Then run: openclaw doctor --fix && openclaw gateway --force"
        echo ""
    fi
fi

if ! command -v python3 &> /dev/null; then
    fail "python3 is required but not found"
fi

if ! command -v curl &> /dev/null; then
    fail "curl is required but not found"
fi

info "Checking gateway..."
if ! openclaw gateway status 2>/dev/null | grep -q "RPC probe: ok"; then
    info "Starting gateway..."
    openclaw gateway start 2>/dev/null || true
    sleep 3
    openclaw gateway status 2>/dev/null | grep -q "RPC probe: ok" || fail "Gateway failed to start. Run: openclaw gateway start"
fi
ok "Gateway running"

# --- Detect skills directory ---

SKILLS_DIR=$(openclaw skills list --json 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['managedSkillsDir'])")
if [ -z "$SKILLS_DIR" ]; then
    fail "Could not detect skills directory"
fi
ok "Skills directory: $SKILLS_DIR"

# --- Dynamically fetch and install skills from repo ---

info "Fetching skill manifest from repository..."
MANIFEST=$(curl -fsSL "$GITHUB_API" 2>/dev/null) || fail "Failed to fetch skill manifest from GitHub"

SKILL_NAMES=$(echo "$MANIFEST" | python3 -c "
import json, sys
items = json.load(sys.stdin)
for item in items:
    if item['type'] == 'dir':
        print(item['name'])
")

if [ -z "$SKILL_NAMES" ]; then
    fail "No skills found in repository manifest"
fi

SKILL_COUNT=0
FAIL_COUNT=0

info "Installing security skills..."
while IFS= read -r skill; do
    install -d -m 755 "$SKILLS_DIR/$skill"
    if curl -fsSL "$GITHUB_RAW/skills/$skill/SKILL.md" -o "$SKILLS_DIR/$skill/SKILL.md" 2>/dev/null; then
        chmod 644 "$SKILLS_DIR/$skill/SKILL.md"
        ok "Installed: $skill"
        SKILL_COUNT=$((SKILL_COUNT + 1))
    else
        warn "Failed to download: $skill"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done <<< "$SKILL_NAMES"

echo ""
ok "Skills installed: $SKILL_COUNT"
if [ "$FAIL_COUNT" -gt 0 ]; then
    warn "Skills failed: $FAIL_COUNT"
fi

# --- Install Clawdex ---

info "Installing Clawdex (Koi Security malicious skill scanner)..."
openclaw skills install clawdex 2>/dev/null && ok "Clawdex installed" || info "Clawdex already installed or unavailable — skipping"

# --- Register nightly cron ---

info "Configuring nightly security cron..."

# Remove any existing nightly-security-patch cron (old or new format)
EXISTING_CRONS=$(openclaw cron list --json 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    jobs = data.get('jobs', [])
    for j in jobs:
        if j.get('name') == 'nightly-security-patch':
            print(j['id'])
except:
    pass
" 2>/dev/null)

if [ -n "$EXISTING_CRONS" ]; then
    while IFS= read -r cron_id; do
        openclaw cron remove "$cron_id" 2>/dev/null && ok "Removed old cron: $cron_id" || true
    done <<< "$EXISTING_CRONS"
fi

# Register new cron with simple prompt — the security-update-manager skill handles the logic
openclaw cron add \
    --name "nightly-security-patch" \
    --every "24h" \
    --description "Hive Financial Systems nightly security maintenance" \
    --session isolated \
    --timeout 120000 \
    --message "Run Hive Financial Systems nightly security maintenance" 2>/dev/null || fail "Failed to register nightly cron"
ok "Nightly security cron registered"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Security Setup Complete!"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "  Skills installed: $SKILL_COUNT"
echo "  Nightly cron: registered (every 24h, isolated session)"
echo ""
echo "  Your bot will automatically pull and apply security"
echo "  updates from the security repo every night."
echo ""
echo "  To activate new skills now, run when no active sessions:"
echo "  openclaw gateway --force"
echo ""
if [ "$CURRENT_VERSION" != "unknown" ]; then
    if [ "$(printf '%s\n' "$MIN_VERSION" "$CURRENT_VERSION" | sort -V | head -n1)" != "$MIN_VERSION" ]; then
        echo "  ⚠️  ACTION REQUIRED: Update OpenClaw to latest version:"
        echo "  npm install -g openclaw@latest"
        echo "  openclaw doctor --fix"
        echo "  openclaw gateway --force"
        echo ""
    fi
fi
