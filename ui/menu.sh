#!/bin/bash

BASE_DIR="/opt/config-deploy"
UI_LOG="$BASE_DIR/logs/ui.log"
DEPLOY_SCRIPT="$BASE_DIR/scripts/deploy.sh"

while true; do
    CHOICE=$(whiptail --title "Zero Downtime Config Deploy" \
        --menu "Choose an action" 15 60 5 \
        "1" "Deploy configuration" \
        "2" "Show current version" \
        "3" "View deploy logs" \
        "4" "Exit" \
        3>&1 1>&2 2>&3)

    [ $? -ne 0 ] && exit 0

    case "$CHOICE" in
        1) "$BASE_DIR/ui/deploy_ui.sh" ;;
        2) "$BASE_DIR/ui/status_ui.sh" ;;
        3) less "$BASE_DIR/logs/deploy.log" ;;
        4) exit 0 ;;
    esac
done
