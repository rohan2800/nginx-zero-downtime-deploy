#!/bin/bash

set -euo pipefail

########################################
# Arguments
########################################

ENV="${1:-}"
VERSION="${2:-}"

########################################
# Paths
########################################

BASE_DIR="/opt/config-deploy"

RELEASE_DIR="$BASE_DIR/releases/$ENV/$VERSION"
CURRENT_LINK="$BASE_DIR/current"
PREVIOUS_LINK="$BASE_DIR/previous"

LOG_FILE="$BASE_DIR/logs/deploy.log"

SWITCH_HELPER="/usr/local/sbin/config-deploy-switch"
HEALTH_CHECK="$BASE_DIR/scripts/health_check.sh"
ROLLBACK="$BASE_DIR/scripts/rollback.sh"
AI_DIAGNOSE="$BASE_DIR/scripts/ai/diagnose.sh"

########################################
# Logging
########################################

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

fail() {
    log "ERROR: $1"
    exit 1
}

########################################
# Argument validation
########################################

if [ -z "$ENV" ] || [ -z "$VERSION" ]; then
    fail "Usage: ./deploy.sh <env> <version>"
fi

########################################
# Environment validation
########################################

case "$ENV" in
    dev|staging|prod)
        ;;
    *)
        fail "Invalid environment: $ENV"
        ;;
esac

########################################
# Release validation
########################################

if [ ! -d "$RELEASE_DIR" ]; then
    fail "Release not found: $RELEASE_DIR"
fi

if [ ! -d "$RELEASE_DIR/site" ]; then
    fail "Website directory not found: $RELEASE_DIR/site"
fi

########################################
# Required component validation
########################################

if [ ! -x "$SWITCH_HELPER" ]; then
    fail "Deployment helper not found or not executable: $SWITCH_HELPER"
fi

if [ ! -x "$HEALTH_CHECK" ]; then
    fail "Health check script not found or not executable: $HEALTH_CHECK"
fi

if [ ! -x "$ROLLBACK" ]; then
    fail "Rollback script not found or not executable: $ROLLBACK"
fi

########################################
# Production approval
########################################

if [ "$ENV" = "prod" ]; then

    echo "========================================"
    echo "       PRODUCTION DEPLOYMENT"
    echo "========================================"
    echo "Environment : $ENV"
    echo "Version     : $VERSION"
    echo "Release     : $RELEASE_DIR"
    echo "========================================"

    read -rp "Type DEPLOY to continue: " CONFIRM

    if [ "$CONFIRM" != "DEPLOY" ]; then
        fail "Production deployment cancelled"
    fi
fi

########################################
# Capture previous release
########################################

PREVIOUS_TARGET=""

if [ -L "$CURRENT_LINK" ]; then
    PREVIOUS_TARGET="$(readlink -f "$CURRENT_LINK" || true)"
fi

if [ -n "$PREVIOUS_TARGET" ]; then

    log "Previous release: $PREVIOUS_TARGET"

    ln -sfn "$PREVIOUS_TARGET" "$PREVIOUS_LINK"

else

    log "No previous release detected"

fi

########################################
# Deployment start
########################################

log "Starting deployment: $ENV $VERSION"

########################################
# Atomic deployment
########################################

if ! sudo "$SWITCH_HELPER" "$RELEASE_DIR"; then

    log "Deployment switch FAILED"

    ####################################
    # AI failure diagnosis
    ####################################

    AI_EVIDENCE="/tmp/config-deploy-ai-evidence.log"

    {
        echo "===== DEPLOYMENT ====="
        echo "Environment: $ENV"
        echo "Version: $VERSION"
        echo "Release: $RELEASE_DIR"

        echo
        echo "===== CURRENT RELEASE ====="
        readlink -f "$CURRENT_LINK" || true

        echo
        echo "===== NGINX CONFIG TEST ====="
        nginx -t 2>&1 || true

        echo
        echo "===== NGINX JOURNAL ====="
        journalctl -u nginx -n 50 --no-pager || true

        echo
        echo "===== DEPLOYMENT LOG ====="
        tail -n 30 "$LOG_FILE" || true

    } > "$AI_EVIDENCE"

    if [ -x "$AI_DIAGNOSE" ]; then

        log "Running AI failure diagnosis"

        "$AI_DIAGNOSE" "$AI_EVIDENCE" \
            | tee -a "$LOG_FILE" || true

    else

        log "AI diagnosis script not available"

    fi

    ####################################
    # Restore previous release
    ####################################

    if [ -n "$PREVIOUS_TARGET" ]; then

        log "Restoring previous release"

        if sudo "$SWITCH_HELPER" "$PREVIOUS_TARGET"; then
            log "Previous release restored"
        else
            log "CRITICAL: Previous release restoration FAILED"
        fi

    fi

    fail "Deployment failed during NGINX switch"

fi

########################################
# Health check
########################################

log "Running health check"

if ! "$HEALTH_CHECK"; then

    log "Health check FAILED"

    ####################################
    # AI evidence collection
    ####################################

    AI_EVIDENCE="/tmp/config-deploy-ai-evidence.log"

    {
        echo "===== DEPLOYMENT ====="
        echo "Environment: $ENV"
        echo "Version: $VERSION"
        echo "Release: $RELEASE_DIR"

        echo
        echo "===== CURRENT RELEASE ====="
        readlink -f "$CURRENT_LINK" || true

        echo
        echo "===== NGINX CONFIG TEST ====="
        nginx -t 2>&1 || true

        echo
        echo "===== NGINX STATUS ====="
        systemctl is-active nginx || true

        echo
        echo "===== NGINX JOURNAL ====="
        journalctl -u nginx -n 50 --no-pager || true

        echo
        echo "===== HEALTH CHECK ====="
        "$HEALTH_CHECK" || true

        echo
        echo "===== DEPLOYMENT LOG ====="
        tail -n 30 "$LOG_FILE" || true

    } > "$AI_EVIDENCE"

    ####################################
    # AI diagnosis
    ####################################

    if [ -x "$AI_DIAGNOSE" ]; then

        log "Running AI failure diagnosis"

        "$AI_DIAGNOSE" "$AI_EVIDENCE" \
            | tee -a "$LOG_FILE" || true

    else

        log "AI diagnosis script not available"

    fi

    ####################################
    # Automatic rollback
    ####################################

    if [ -n "$PREVIOUS_TARGET" ]; then

        log "Starting automatic rollback"

        if "$ROLLBACK"; then

            log "Automatic rollback successful"

        else

            fail "CRITICAL: Automatic rollback FAILED"

        fi

    else

        log "No previous release available for rollback"

    fi

    fail "Deployment failed health check"

fi

########################################
# Deployment success
########################################

log "Health check PASSED"

log "Active release: $(readlink -f "$CURRENT_LINK")"

log "Deployment successful: $ENV $VERSION"

exit 0
