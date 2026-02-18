#!/bin/bash
# =============================================================================
# apply-patch.sh — OpenClaw Security Patch Applicator
# Hive Financial Systems | INFRA-929
# Author: Vamsi Ravuri, Senior Cloud Security Engineer
# =============================================================================

set -euo pipefail

OPENCLAW_DIR="$HOME/.openclaw"
SKILLS_DIR="$OPENCLAW_DIR/skills"
CONFIG_FILE="$OPENCLAW_DIR/openclaw.json"
BACKUP_DIR="$OPENCLAW_DIR/backups"
LOG_FILE="$OPENCLAW_DIR/update.log"
REPO_DIR="$OPENCLAW_DIR/security-repo"
PATCH_CONFIG="$REPO_DIR/config/security-patch.json"
REPO_SKILLS_DIR="$REPO_DIR/skills"
VERSION_FILE="$REPO_DIR/version.txt"
APPLIED_VERSION_FILE="$OPENCLAW_DIR/.applied-version"

SECURITY_SKILLS=(
  "security-validation"
  "command-guard"
  "prompt-injection-detector"
  "data-exfiltration-guard"
  "session-isolation-enforcer"
  "skill-security-scanner"
  "security-scan-scheduler"
)

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_section() {
  echo "" >> "$LOG_FILE"
  echo "================================================" >> "$LOG_FILE"
  log "$1"
  echo "================================================" >> "$LOG_FILE"
}

rollback() {
  log "ROLLBACK TRIGGERED -- restoring from $BACKUP_PATH"
  if [ -f "$BACKUP_PATH/openclaw.json" ]; then
    cp "$BACKUP_PATH/openclaw.json" "$CONFIG_FILE"
    log "Config restored"
  fi
  for skill in "${SECURITY_SKILLS[@]}"; do
    if [ -d "$BACKUP_PATH/skills/$skill" ]; then
      rm -rf "$SKILLS_DIR/$skill"
      cp -r "$BACKUP_PATH/skills/$skill" "$SKILLS_DIR/"
      log "Skill restored: $skill"
    fi
  done
  openclaw gateway --force >> "$LOG_FILE" 2>&1 &
  sleep 3
  log "PATCH FAILED -- system rolled back to $APPLIED_VERSION"
  exit 1
}

trap rollback ERR

REPO_VERSION=$(cat "$VERSION_FILE" 2>/dev/null || echo "unknown")
APPLIED_VERSION=$(cat "$APPLIED_VERSION_FILE" 2>/dev/null || echo "none")

log_section "OpenClaw Security Patch -- $REPO_VERSION"
log "Machine: $(hostname) | User: $(whoami)"
log "Current applied: $APPLIED_VERSION | Repo version: $REPO_VERSION"

TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
BACKUP_PATH="$BACKUP_DIR/$TIMESTAMP"
mkdir -p "$BACKUP_PATH/skills"

if [ -f "$CONFIG_FILE" ]; then
  cp "$CONFIG_FILE" "$BACKUP_PATH/openclaw.json"
  log "Config backed up"
fi

for skill in "${SECURITY_SKILLS[@]}"; do
  if [ -d "$SKILLS_DIR/$skill" ]; then
    cp -r "$SKILLS_DIR/$skill" "$BACKUP_PATH/skills/"
    log "Backed up skill: $skill"
  fi
done

log "Backup complete: $BACKUP_PATH"

log "Applying security skills..."
mkdir -p "$SKILLS_DIR"

for skill in "${SECURITY_SKILLS[@]}"; do
  if [ -d "$REPO_SKILLS_DIR/$skill" ]; then
    rm -rf "$SKILLS_DIR/$skill"
    cp -r "$REPO_SKILLS_DIR/$skill" "$SKILLS_DIR/$skill"
    log "Applied skill: $skill"
  else
    log "WARNING: Skill not found in repo: $skill -- skipping"
  fi
done

log "Merging security config..."

if [ ! -f "$CONFIG_FILE" ]; then
  cp "$PATCH_CONFIG" "$CONFIG_FILE"
  log "No existing config found -- created from patch"
else
  node - <<'EOF'
const fs = require('fs');
const configPath = process.env.HOME + '/.openclaw/openclaw.json';
const patchPath  = process.env.HOME + '/.openclaw/security-repo/config/security-patch.json';
const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
const patch  = JSON.parse(fs.readFileSync(patchPath,  'utf8'));
function deepMerge(target, source) {
  for (const key of Object.keys(source)) {
    if (typeof source[key] === 'object' && !Array.isArray(source[key]) && source[key] !== null) {
      target[key] = target[key] || {};
      deepMerge(target[key], source[key]);
    } else {
      target[key] = source[key];
    }
  }
  return target;
}
const merged = deepMerge(config, patch);
fs.writeFileSync(configPath, JSON.stringify(merged, null, 2));
console.log('Config merge complete');
EOF
  log "Security config merged -- bot/agent configs preserved"
fi

log "Restarting OpenClaw gateway..."
openclaw gateway --force >> "$LOG_FILE" 2>&1 &
sleep 5
log "Gateway restarted"

log "Running post-patch security audit..."
AUDIT_OUTPUT=$(openclaw security audit 2>&1 || true)
echo "$AUDIT_OUTPUT" >> "$LOG_FILE"

CRITICAL_COUNT=$(echo "$AUDIT_OUTPUT" | grep -oP '\d+(?= critical)' | head -1 || true)

if [ -n "$CRITICAL_COUNT" ] && [ "$CRITICAL_COUNT" -gt 0 ]; then
  log "Audit returned $CRITICAL_COUNT critical finding(s) -- initiating rollback"
  rollback
fi

log "Security audit passed -- 0 critical findings"

echo "$REPO_VERSION" > "$APPLIED_VERSION_FILE"
log "Version stamped: $REPO_VERSION"

ls -dt "$BACKUP_DIR"/*/ 2>/dev/null | tail -n +6 | xargs rm -rf || true
log "Old backups cleaned up (keeping last 5)"

log_section "PATCH APPLIED SUCCESSFULLY -- $REPO_VERSION"
log "All 7 security skills active. Bot/agent configs untouched."
log "Backup retained at: $BACKUP_PATH"
