#!/bin/bash

set -euo pipefail

BASE_DIR="/opt/config-deploy"
CURRENT_LINK="$BASE_DIR/current"
PREVIOUS_LINK="$BASE_DIR/previous"
LOG_FILE="$BASE_DIR/logs/deploy.log"

SWITCH_HELPER="/usr/local/sbin/config-deploy-switch"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

if [ ! -L "$PREVIOUS_LINK" ]; then
    log "ERROR: No previous release available"
    exit 1
fi

PREVIOUS_TARGET="$(readlink -f "$PREVIOUS_LINK")"

if [ ! -d "$PREVIOUS_TARGET/site" ]; then
    log "ERROR: Previous site directory missing"
    exit 1
fi

log "Rolling back to: $PREVIOUS_TARGET"

sudo "$SWITCH_HELPER" "$PREVIOUS_TARGET"

log "Rollback successful"
