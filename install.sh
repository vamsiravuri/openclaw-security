#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
# OpenClaw Security Hardening — Unified Installer
# Hive Financial Systems
#
# One script, all machines. Combines:
#   - 7 security skills (command-guard, prompt-injection-detector, etc.)
#   - Safe config patch (sandbox + caps + mDNS)
#   - OpenClaw update to 2026.2.15+
#   - Native security audit
#   - Clawdex (Koi Security live scanner)
#
# What this does NOT do:
#   - Does NOT set network: "none" (agents keep network access)
#   - Does NOT set workspaceAccess: "ro" (agents keep write access)
#   - Does NOT block browser/canvas tools
#   - Does NOT touch gateway, channels, agents, auth, session, or plugins
# ═══════════════════════════════════════════════════════════════════
set -eo pipefail

GITHUB_RAW="https://raw.githubusercontent.com/vamsiravuri/openclaw-security/release"
GITHUB_REPO="https://github.com/vamsiravuri/openclaw-security"
if [[ -n "${BASH_SOURCE[0]:-}" ]] && [[ "${BASH_SOURCE[0]}" != "bash" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  PIPE_MODE=false
else
  SCRIPT_DIR="$(mktemp -d)"
  PIPE_MODE=true
  echo "[INFO] Pipe mode detected -- downloading assets from GitHub..."
  curl -fsSL "$GITHUB_RAW/security-patch.json" -o "$SCRIPT_DIR/security-patch.json"
  mkdir -p "$SCRIPT_DIR/skills/security-validation"
  mkdir -p "$SCRIPT_DIR/skills/command-guard"
  mkdir -p "$SCRIPT_DIR/skills/prompt-injection-detector"
  mkdir -p "$SCRIPT_DIR/skills/data-exfiltration-guard"
  mkdir -p "$SCRIPT_DIR/skills/session-isolation-enforcer"
  mkdir -p "$SCRIPT_DIR/skills/skill-security-scanner/scripts"
  mkdir -p "$SCRIPT_DIR/skills/security-scan-scheduler"
  curl -fsSL "$GITHUB_RAW/skills/security-validation/SKILL.md" -o "$SCRIPT_DIR/skills/security-validation/SKILL.md"
  curl -fsSL "$GITHUB_RAW/skills/command-guard/SKILL.md" -o "$SCRIPT_DIR/skills/command-guard/SKILL.md"
  curl -fsSL "$GITHUB_RAW/skills/prompt-injection-detector/SKILL.md" -o "$SCRIPT_DIR/skills/prompt-injection-detector/SKILL.md"
  curl -fsSL "$GITHUB_RAW/skills/data-exfiltration-guard/SKILL.md" -o "$SCRIPT_DIR/skills/data-exfiltration-guard/SKILL.md"
  curl -fsSL "$GITHUB_RAW/skills/session-isolation-enforcer/SKILL.md" -o "$SCRIPT_DIR/skills/session-isolation-enforcer/SKILL.md"
  curl -fsSL "$GITHUB_RAW/skills/skill-security-scanner/SKILL.md" -o "$SCRIPT_DIR/skills/skill-security-scanner/SKILL.md"
  curl -fsSL "$GITHUB_RAW/skills/skill-security-scanner/scripts/scan_skill.py" -o "$SCRIPT_DIR/skills/skill-security-scanner/scripts/scan_skill.py"
  curl -fsSL "$GITHUB_RAW/skills/security-scan-scheduler/SKILL.md" -o "$SCRIPT_DIR/skills/security-scan-scheduler/SKILL.md"
  echo "[OK] Assets downloaded"
fi
OPENCLAW_DIR="$HOME/.openclaw"
CONFIG_FILE="$OPENCLAW_DIR/openclaw.json"
SKILLS_DIR="$OPENCLAW_DIR/skills"
BACKUP_DIR="$OPENCLAW_DIR/backups"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
fail()  { echo -e "${RED}[FAIL]${NC} $1"; }
step()  { echo -e "\n${CYAN}═══ STEP $1 ═══${NC}"; }

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  OpenClaw Security Hardening — Hive Financial Systems"
echo "  Unified Installer"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# ── Auto-install OpenClaw if not present ─────────────────────────
if ! command -v openclaw &> /dev/null; then
    warn "OpenClaw not found -- installing now..."
    if ! command -v npm &> /dev/null; then
        fail "npm not found. Install Node.js v22.12.0+ first: https://nodejs.org"
        fail "  macOS:      brew install node"
        fail "  Ubuntu/WSL: curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - && sudo apt install -y nodejs"
        exit 1
    fi
    info "Installing OpenClaw via npm..."
    sudo npm install -g openclaw 2>&1 | tail -5
    if ! command -v openclaw &> /dev/null; then
        fail "OpenClaw install failed. Install manually: sudo npm install -g openclaw"
        exit 1
    fi
    ok "OpenClaw installed"
    info "Running openclaw setup..."
    openclaw setup --non-interactive 2>&1 || true
    sleep 2
fi

CURRENT_VERSION=$(openclaw --version 2>/dev/null | head -1)
info "Current version: $CURRENT_VERSION"

# ── Auto-install Docker if not present ───────────────────────────
if ! command -v docker &> /dev/null; then
    warn "Docker not found -- installing now..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        if command -v brew &> /dev/null; then
            brew install --cask docker 2>&1 | tail -5
            open /Applications/Docker.app || true
            sleep 5
        else
            fail "Homebrew not found. Install Docker Desktop manually: https://docs.docker.com/desktop/install/mac-install/"
            exit 1
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        sudo apt-get update -qq 2>&1 | tail -2
        sudo apt-get install -y docker.io 2>&1 | tail -5
        sudo systemctl start docker 2>&1 || true
        sudo usermod -aG docker "$USER" 2>&1 || true
    fi
    if ! command -v docker &> /dev/null; then
        fail "Docker install failed. Install manually then re-run."
        exit 1
    fi
    ok "Docker installed"
fi
ok "Docker found"

# ── Auto-install Python3 if not present ──────────────────────────
if ! command -v python3 &> /dev/null; then
    warn "Python 3 not found -- installing now..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        if command -v brew &> /dev/null; then
            brew install python3 2>&1 | tail -5
        else
            fail "Homebrew not found. Install Python 3 manually: https://www.python.org/downloads/"
            exit 1
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        sudo apt-get update -qq 2>&1 | tail -2
        sudo apt-get install -y python3 2>&1 | tail -5
    fi
    if ! command -v python3 &> /dev/null; then
        fail "Python 3 install failed. Install manually then re-run."
        exit 1
    fi
    ok "Python 3 installed"
fi
ok "Python 3 found"

# ── Auto-run openclaw setup if config missing ─────────────────────
if [[ ! -f "$CONFIG_FILE" ]]; then
    warn "openclaw.json not found -- running openclaw setup..."
    openclaw setup --non-interactive 2>&1 || true
    sleep 2
    if [[ ! -f "$CONFIG_FILE" ]]; then
        fail "Setup failed. Run 'openclaw setup' manually then re-run this script."
        exit 1
    fi
    ok "openclaw setup complete"
fi

# Detect platform
OS_TYPE="unknown"
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS_TYPE="macOS"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    if grep -qi microsoft /proc/version 2>/dev/null; then
        OS_TYPE="WSL"
    else
        OS_TYPE="Linux"
    fi
fi
ok "Platform: $OS_TYPE"

# Backup
mkdir -p "$BACKUP_DIR"
cp "$CONFIG_FILE" "$BACKUP_DIR/openclaw.json.backup-$TIMESTAMP"
ok "Backup saved: $BACKUP_DIR/openclaw.json.backup-$TIMESTAMP"

# ══════════════════════════════════════════════════════════════════
step "1/7 — Update OpenClaw"
# ══════════════════════════════════════════════════════════════════

info "Checking for updates..."

# Detect install method
if [[ -L "$(which openclaw 2>/dev/null)" ]] && readlink "$(which openclaw)" 2>/dev/null | grep -q "node_modules"; then
    INSTALL_METHOD="npm-global"
elif command -v npm &> /dev/null && npm list -g openclaw &> /dev/null; then
    INSTALL_METHOD="npm"
elif [[ -d "$HOME/.openclaw/.git" ]] || [[ -d "/opt/openclaw/.git" ]]; then
    INSTALL_METHOD="source"
else
    INSTALL_METHOD="unknown"
fi

info "Install method: $INSTALL_METHOD"

case "$INSTALL_METHOD" in
    npm-global)
        info "Updating via npm (global)..."
        sudo npm update -g openclaw 2>&1 | tail -5
        ;;
    npm)
        info "Updating via npm..."
        npm update -g openclaw 2>&1 | tail -5
        ;;
    source)
        info "Source install — running openclaw update..."
        openclaw update 2>&1 | tail -5 || warn "openclaw update failed — update manually"
        ;;
    *)
        info "Trying openclaw update..."
        openclaw update 2>&1 | tail -5 || {
            warn "Could not auto-update. Update manually:"
            echo "    npm: sudo npm update -g openclaw"
            echo "    source: cd <openclaw-repo> && git pull && npm install"
            echo ""
            read -p "Press Enter after updating (or to skip)..."
        }
        ;;
esac

NEW_VERSION=$(openclaw --version 2>/dev/null | head -1)
if [[ "$NEW_VERSION" != "$CURRENT_VERSION" ]]; then
    ok "Updated: $CURRENT_VERSION → $NEW_VERSION"
else
    info "Version: $NEW_VERSION (already latest)"
fi

# ══════════════════════════════════════════════════════════════════
step "2/7 — Apply Security Config"
# ══════════════════════════════════════════════════════════════════

info "Merging security config patch..."

export SCRIPT_DIR
python3 << 'MERGE_SCRIPT'
import json
import os
from pathlib import Path
from copy import deepcopy

config_file = Path.home() / ".openclaw" / "openclaw.json"
patch_file = Path(os.environ["SCRIPT_DIR"]) / "security-patch.json"  # works for both local and pipe mode

def deep_merge(base, patch):
    result = deepcopy(base)
    for key, value in patch.items():
        if key.startswith("_"):
            continue
        if key in result and isinstance(result[key], dict) and isinstance(value, dict):
            result[key] = deep_merge(result[key], value)
        else:
            result[key] = deepcopy(value)
    return result

cfg = json.loads(config_file.read_text())
patch = json.loads(patch_file.read_text())
merged = deep_merge(cfg, patch)

# Safety: remove over-restrictive keys if present from older versions
sandbox = merged.get("agents", {}).get("defaults", {}).get("sandbox", {})
docker = sandbox.get("docker", {})

# Remove network: "none" — agents need network access
if docker.get("network") == "none":
    del docker["network"]
    print("  Removed: network=none (agents keep network)")

# Remove network: "host" — blocked in 2026.2.15
if docker.get("network") == "host":
    docker["network"] = "bridge"
    print("  Fixed: network=host → bridge (host blocked in 2026.2.15)")

# Remove workspaceAccess: "ro" — agents need write access
if sandbox.get("workspaceAccess") == "ro":
    del sandbox["workspaceAccess"]
    print("  Removed: workspaceAccess=ro (agents keep rw)")

# Ensure tools.deny only has "nodes", not browser/canvas
tools = merged.get("tools", {})
deny = tools.get("deny", [])
if "browser" in deny or "canvas" in deny:
    tools["deny"] = ["nodes"]
    print("  Fixed: tools.deny → ['nodes'] only (browser/canvas unblocked)")

config_file.write_text(json.dumps(merged, indent=2) + "\n")
print("  Config merged successfully")
MERGE_SCRIPT

ok "Security config applied"

# ══════════════════════════════════════════════════════════════════
step "3/7 — Install Security Skills"
# ══════════════════════════════════════════════════════════════════

info "Installing 7 security skills..."
mkdir -p "$SKILLS_DIR"

SKILLS=(
    "security-validation"
    "command-guard"
    "prompt-injection-detector"
    "data-exfiltration-guard"
    "session-isolation-enforcer"
    "skill-security-scanner"
    "security-scan-scheduler"
)

for skill in "${SKILLS[@]}"; do
    src="$SCRIPT_DIR/skills/$skill"
    dst="$SKILLS_DIR/$skill"

    if [[ -d "$dst" ]]; then
        # Back up and replace
        mv "$dst" "$BACKUP_DIR/${skill}.backup-$TIMESTAMP" 2>/dev/null || true
    fi

    cp -r "$src" "$dst"
    ok "Installed: $skill"
done

# Make scanner script executable
chmod +x "$SKILLS_DIR/skill-security-scanner/scripts/scan_skill.py" 2>/dev/null || true

# ══════════════════════════════════════════════════════════════════
step "4/7 — Install Clawdex (Koi Security)"
# ══════════════════════════════════════════════════════════════════

info "Clawdex provides live scanning against known malicious skills (341+ flagged)."

if [[ -d "$SKILLS_DIR/clawdex" ]]; then
    info "Clawdex already installed — skipping"
else
    # Method 1: clawhub CLI
    if command -v clawhub &> /dev/null; then
        info "Installing via clawhub CLI..."
        clawhub install clawdex --workdir "$OPENCLAW_DIR" --no-input 2>&1 || {
            warn "clawhub install failed"
        }
    fi

    # Method 2: Install clawhub CLI then install clawdex
    if [[ ! -d "$SKILLS_DIR/clawdex" ]] && command -v npm &> /dev/null; then
        info "Installing clawhub CLI..."
        npm i -g clawhub 2>&1 | tail -3
        if command -v clawhub &> /dev/null; then
            clawhub install clawdex --workdir "$OPENCLAW_DIR" --no-input 2>&1 || {
                warn "clawhub install failed after CLI setup"
            }
        fi
    fi

    # Method 3: Manual fallback
    if [[ ! -d "$SKILLS_DIR/clawdex" ]]; then
        warn "Could not install Clawdex automatically."
        echo "  Install manually: clawhub install clawdex --workdir ~/.openclaw"
    fi
fi

if [[ -d "$SKILLS_DIR/clawdex" ]]; then
    ok "Clawdex installed"
fi

# ══════════════════════════════════════════════════════════════════
step "5/7 — Run Security Audit"
# ══════════════════════════════════════════════════════════════════

info "Running openclaw security audit --fix..."
echo ""
openclaw security audit --fix 2>&1 || warn "Audit returned warnings"
echo ""

info "Running deep audit..."
echo ""
openclaw security audit --deep 2>&1 || warn "Deep audit returned warnings"
echo ""

ok "Security audit complete"

# ══════════════════════════════════════════════════════════════════
step "6/7 — Verify Installation"
# ══════════════════════════════════════════════════════════════════

echo ""
echo "  Config verification:"

python3 << 'VERIFY_SCRIPT'
import json
from pathlib import Path

cfg = json.loads((Path.home()/".openclaw"/"openclaw.json").read_text())

sandbox = cfg.get("agents",{}).get("defaults",{}).get("sandbox",{})
docker = sandbox.get("docker",{})
tools = cfg.get("tools",{})

checks = [
    ("sandbox.mode",            sandbox.get("mode"),                      "all"),
    ("sandbox.scope",           sandbox.get("scope"),                     "session"),
    ("docker.readOnlyRoot",     docker.get("readOnlyRoot"),               True),
    ("docker.capDrop",          docker.get("capDrop"),                    ["ALL"]),
    ("tools.elevated",          tools.get("elevated",{}).get("enabled"),  False),
    ("tools.deny",              tools.get("deny"),                        ["nodes"]),
    ("discovery.mdns",          cfg.get("discovery",{}).get("mdns",{}).get("mode"), "off"),
]

all_pass = True
for name, actual, expected in checks:
    if actual == expected:
        print(f"    ✅ {name} = {actual}")
    else:
        print(f"    ❌ {name} = {actual} (expected: {expected})")
        all_pass = False

# Confirm dangerous settings NOT present
net = docker.get("network")
ws = sandbox.get("workspaceAccess")
deny = tools.get("deny", [])

if net == "none":
    print("    ❌ network=none is set (should not be)")
    all_pass = False
if ws == "ro":
    print("    ❌ workspaceAccess=ro is set (should not be)")
    all_pass = False
if "browser" in deny or "canvas" in deny:
    print("    ❌ browser/canvas blocked (should not be)")
    all_pass = False

# Show untouched user config
gw = cfg.get("gateway", {})
ch = cfg.get("channels", {})
ag = cfg.get("agents", {}).get("list", [])
print(f"\n    ℹ️  gateway.port = {gw.get('port', 'default')} (untouched)")
print(f"    ℹ️  agents count = {len(ag)} (untouched)")

if all_pass:
    print("\n    ✅ All security checks passed!")
else:
    print("\n    ⚠️  Some checks need attention — review above")
VERIFY_SCRIPT

echo ""
echo "  Skills verification:"

ALL_SKILLS=(
    "security-validation"
    "command-guard"
    "prompt-injection-detector"
    "data-exfiltration-guard"
    "session-isolation-enforcer"
    "skill-security-scanner"
    "security-scan-scheduler"
)

MISSING=0
for skill in "${ALL_SKILLS[@]}"; do
    if [[ -f "$SKILLS_DIR/$skill/SKILL.md" ]]; then
        echo -e "    ${GREEN}✅${NC} $skill"
    else
        echo -e "    ${RED}❌${NC} $skill — MISSING"
        MISSING=$((MISSING + 1))
    fi
done

if [[ -d "$SKILLS_DIR/clawdex" ]]; then
    echo -e "    ${GREEN}✅${NC} clawdex (Koi Security)"
else
    echo -e "    ${YELLOW}⚠️${NC}  clawdex — install manually after restart"
fi

echo ""

# Node.js version check
NODE_VERSION=$(node --version 2>/dev/null || echo "not found")
if [[ "$NODE_VERSION" != "not found" ]]; then
    NODE_MAJOR=$(echo "$NODE_VERSION" | sed 's/v//' | cut -d. -f1)
    NODE_MINOR=$(echo "$NODE_VERSION" | sed 's/v//' | cut -d. -f2)
    if [[ "$NODE_MAJOR" -ge 22 && "$NODE_MINOR" -ge 12 ]]; then
        echo -e "  Node.js: $NODE_VERSION ${GREEN}✅${NC}"
    else
        echo -e "  Node.js: $NODE_VERSION ${RED}— update to 22.12.0+${NC}"
    fi
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo -e "  ${GREEN}Security Hardening Complete!${NC}"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "  Next steps:"
echo "    1. Restart gateway:  openclaw gateway --force"
echo "    2. Review any audit warnings above"
echo "    3. Rotate credentials if needed"
echo ""
echo "  Backup: $BACKUP_DIR/openclaw.json.backup-$TIMESTAMP"
echo "  Rollback: cp $BACKUP_DIR/openclaw.json.backup-$TIMESTAMP $CONFIG_FILE"
echo ""

# ══════════════════════════════════════════════════════════════════
step "7/7 — Enroll Pull Agent"
# ══════════════════════════════════════════════════════════════════

info "Setting up automated security patch distribution..."

SECURITY_REPO_DIR="$OPENCLAW_DIR/security-repo"
RING_FILE="$OPENCLAW_DIR/.ring"
PULL_AGENT="$SECURITY_REPO_DIR/pull-agent.sh"
APPLY_PATCH="$SECURITY_REPO_DIR/apply-patch.sh"

# Issue 3 fix: pre-flight check for git
if ! command -v git &> /dev/null; then
  fail "git not found. Install git and re-run this script."
  fail "  Ubuntu/WSL: sudo apt install git"
  fail "  macOS:      xcode-select --install"
  exit 1
fi
ok "git found"

SECURITY_REPO_URL="https://github.com/vamsiravuri/openclaw-security.git"

# Clone or update the security repo
if [ -d "$SECURITY_REPO_DIR/.git" ]; then
  info "Security repo already cloned -- updating..."
  cd "$SECURITY_REPO_DIR"
  CURRENT_RING=$(cat "$RING_FILE" 2>/dev/null || echo "main")
  if ! git fetch origin >> /dev/null 2>&1; then
    fail "Failed to reach security repo -- check network connectivity"
    exit 1
  fi
  git checkout "$CURRENT_RING" >> /dev/null 2>&1
  git pull origin "$CURRENT_RING" >> /dev/null 2>&1
  ok "Security repo updated"
else
  info "Cloning security repo (branch: release)..."
  if ! git clone --branch release "$SECURITY_REPO_URL" "$SECURITY_REPO_DIR" >> /dev/null 2>&1; then
    fail "Failed to clone security repo -- check network connectivity and re-run"
    exit 1
  fi
  ok "Security repo cloned"
fi

# Verify clone succeeded and scripts exist
if [ ! -f "$PULL_AGENT" ]; then
  fail "pull-agent.sh not found after clone -- repo may be incomplete"
  fail "Contact Vamsi Ravuri (vamsi.ravuri@hivefs.com)"
  exit 1
fi

if [ ! -f "$APPLY_PATCH" ]; then
  fail "apply-patch.sh not found after clone -- repo may be incomplete"
  fail "Contact Vamsi Ravuri (vamsi.ravuri@hivefs.com)"
  exit 1
fi

ok "pull-agent.sh verified"
ok "apply-patch.sh verified"

# Make scripts executable
chmod +x "$PULL_AGENT"
chmod +x "$APPLY_PATCH"

# Set ring assignment -- all machines default to main (Ring 2)
# Ring 0 (Vamsi/dev) and Ring 1 (Ben/release) are set manually
if [ ! -f "$RING_FILE" ]; then
  echo "main" > "$RING_FILE"
  ok "Ring assignment set: main (Ring 2 -- receives patches after full validation)"
else
  info "Ring assignment already set: $(cat $RING_FILE) -- skipping"
fi

# Issue 4 fix: Register cron job with full paths (no ~ expansion issues in cron)
CRON_JOB="0 2 * * * bash $PULL_AGENT >> $OPENCLAW_DIR/update.log 2>&1"
if crontab -l 2>/dev/null | grep -q "pull-agent.sh"; then
  info "Pull agent cron job already registered -- skipping"
else
  (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
  ok "Pull agent cron job registered (runs nightly at 2AM)"
fi

# Verify cron registration
if crontab -l 2>/dev/null | grep -q "pull-agent.sh"; then
  ok "Cron job verified in crontab"
else
  warn "Cron job registration could not be verified -- check crontab manually: crontab -l"
fi

ok "Pull agent enrolled -- this machine will receive security patches automatically"

# Cleanup temp dir if pipe mode
if [[ "$PIPE_MODE" == true ]]; then
  rm -rf "$SCRIPT_DIR"
fi
ok "Patches flow: Vamsi pushes to dev → validated 24h → release → validated 48h → main (this machine)"
