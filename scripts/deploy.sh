#!/bin/bash
set -euo pipefail

########################################
# Arguments
########################################
ENV="${1:?Usage: deploy.sh <env> <version>}"
VERSION="${2:?Usage: deploy.sh <env> <version>}"

########################################
# Paths
########################################
BASE="/opt/config-deploy"
RELEASE_DIR="$BASE/releases/$ENV/$VERSION"
CURRENT="$BASE/current"
LOG="$BASE/logs/deploy.log"
AUDIT="$BASE/audit/deploy.log"

########################################
# Helpers
########################################
log() {
    echo "[$(date '+%F %T')] $1" | tee -a "$LOG"
}

fail() {
    log "ERROR: $1"
    echo "$(date '+%F %T') | $USER | $ENV | $VERSION | FAILED" >> "$AUDIT"
    exit 1
}

health_check() {
    curl -sf "http://localhost:$HEALTH_PORT" >/dev/null
}

########################################
# Environment validation
########################################
case "$ENV" in
    dev|staging|prod) ;;
    *) fail "Invalid environment: $ENV" ;;
esac

########################################
# 7.3 Health port per environment
########################################
case "$ENV" in
    dev) HEALTH_PORT=8080 ;;
    staging) HEALTH_PORT=8081 ;;
    prod) HEALTH_PORT=80 ;;
esac

########################################
# Validation
########################################
[ -d "$RELEASE_DIR" ] || fail "Release not found: $RELEASE_DIR"

########################################
# Capture previous version
########################################
PREVIOUS="$(readlink -f "$CURRENT" || true)"

log "Deploying $VERSION to $ENV"

########################################
# ENV specific rules (prod safety)
########################################
if [ "$ENV" = "prod" ]; then
    log "PRODUCTION DEPLOYMENT"
    read -rp "Type DEPLOY to continue: " CONFIRM
    [ "$CONFIRM" = "DEPLOY" ] || fail "Prod deploy aborted"
    sleep 5
fi

########################################
# Atomic symlink switch
########################################
ln -sfn "$RELEASE_DIR" "$CURRENT"

########################################
# Validate nginx config
########################################
if ! nginx -t; then
    log "Validation failed — rolling back"
    [ -n "$PREVIOUS" ] && ln -sfn "$PREVIOUS" "$CURRENT"
    nginx -t || fail "Rollback validation failed"
    systemctl reload nginx
    fail "Deployment rolled back"
fi

########################################
# Reload nginx
########################################
systemctl reload nginx

########################################
# 7.4 Health check + auto rollback
########################################
sleep 2

if ! health_check; then
    log "Health check failed — rolling back"
    [ -n "$PREVIOUS" ] && ln -sfn "$PREVIOUS" "$CURRENT"
    systemctl reload nginx
    fail "Rollback due to failed health check"
fi

########################################
# Audit success
########################################
echo "$(date '+%F %T') | $USER | $ENV | $VERSION | SUCCESS" >> "$AUDIT"
log "Deployment successful"
