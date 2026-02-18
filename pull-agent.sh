#!/bin/bash
# =============================================================================
# pull-agent.sh — OpenClaw Security Patch Pull Agent
# Hive Financial Systems | INFRA-929
# Runs nightly via cron. Pulls from Azure Git based on ring assignment.
# Ring: dev (Ring 0 - Vamsi) | release (Ring 1 - Ben) | main (Ring 2 - All)
# =============================================================================
set -euo pipefail

OPENCLAW_DIR="$HOME/.openclaw"
REPO_DIR="$OPENCLAW_DIR/security-repo"
LOG_FILE="$OPENCLAW_DIR/update.log"
RING_FILE="$OPENCLAW_DIR/.ring"
APPLIED_VERSION_FILE="$OPENCLAW_DIR/.applied-version"
APPLY_SCRIPT="$REPO_DIR/apply-patch.sh"
LOCK_FILE="/tmp/openclaw-pull-agent.lock"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [PULL-AGENT] $1" | tee -a "$LOG_FILE"
}

# Prevent overlapping runs
if [ -f "$LOCK_FILE" ]; then
  log "Another pull-agent instance is running. Exiting."
  exit 0
fi
touch "$LOCK_FILE"
trap "rm -f $LOCK_FILE" EXIT

# Read ring assignment
if [ ! -f "$RING_FILE" ]; then
  log "ERROR: No ring assignment found at $RING_FILE"
  log "Run install.sh to set up this machine properly."
  exit 1
fi

RING=$(cat "$RING_FILE" | tr -d '[:space:]')
log "Machine: $(hostname) | Ring: $RING | Branch: $RING"

if [[ "$RING" != "dev" && "$RING" != "release" && "$RING" != "main" ]]; then
  log "ERROR: Invalid ring assignment '$RING'. Must be dev, release, or main."
  exit 1
fi

# Git pull
if [ ! -d "$REPO_DIR/.git" ]; then
  log "ERROR: Repo not found at $REPO_DIR. Run install.sh first."
  exit 1
fi

log "Pulling from branch: $RING"
cd "$REPO_DIR"
git fetch origin >> "$LOG_FILE" 2>&1

# Check for changes
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse "origin/$RING")

if [ "$LOCAL" = "$REMOTE" ]; then
  log "Already up to date. Nothing to apply."
  exit 0
fi

log "Changes detected -- pulling..."
git checkout "$RING" >> "$LOG_FILE" 2>&1
git pull origin "$RING" >> "$LOG_FILE" 2>&1
log "Pull complete"

# Version check
REPO_VERSION=$(cat "$REPO_DIR/version.txt" 2>/dev/null || echo "unknown")
APPLIED_VERSION=$(cat "$APPLIED_VERSION_FILE" 2>/dev/null || echo "none")
log "Repo version: $REPO_VERSION | Applied version: $APPLIED_VERSION"

if [ "$REPO_VERSION" = "$APPLIED_VERSION" ]; then
  log "Version already applied. Nothing to do."
  exit 0
fi

# Breaking change check
if grep -q "\[BREAKING\]" "$REPO_DIR/CHANGELOG.md" 2>/dev/null; then
  BREAKING_LINE=$(grep "\[BREAKING\]" "$REPO_DIR/CHANGELOG.md" | head -1)
  log "BREAKING CHANGE DETECTED: $BREAKING_LINE"
  log "Auto-apply SKIPPED. Manual review required by Vamsi."
  log "To apply manually after review: bash $APPLY_SCRIPT"
  exit 0
fi

# Apply patch
log "Invoking apply-patch.sh..."
bash "$APPLY_SCRIPT"
log "Pull agent cycle complete."
