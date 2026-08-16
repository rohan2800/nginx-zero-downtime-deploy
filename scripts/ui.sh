#!/bin/bash

set -u

########################################
# Configuration
########################################

BASE_DIR="/opt/config-deploy"

DEPLOY="$BASE_DIR/scripts/deploy.sh"
ROLLBACK="$BASE_DIR/scripts/rollback.sh"
HEALTH="$BASE_DIR/scripts/health_check.sh"
AI="$BASE_DIR/scripts/ai/diagnose.sh"

LOG="$BASE_DIR/logs/deploy.log"

AI_EVIDENCE="/tmp/config-deploy-ai-evidence.log"

########################################
# Check dependencies
########################################

if ! command -v whiptail >/dev/null 2>&1; then
    echo "ERROR: whiptail is not installed."
    echo "Install with: sudo apt install whiptail -y"
    exit 1
fi

########################################
# Helper: Message Box
########################################

message() {

    whiptail \
        --title "Zero-Downtime Deployment" \
        --msgbox "$1" \
        12 70
}

########################################
# Helper: Run Command
########################################

run_command() {

    OUTPUT_FILE="/tmp/config-deploy-ui-output.log"
    RAW_OUTPUT="/tmp/config-deploy-ui-raw.log"

    if "$@" >"$RAW_OUTPUT" 2>&1; then
        RESULT=0
    else
        RESULT=$?
    fi

    # Remove ANSI terminal control sequences
    sed -E 's/\x1B\[[0-9;?]*[ -\/]*[@-~]//g' \
        "$RAW_OUTPUT" > "$OUTPUT_FILE"

    if [ "$RESULT" -eq 0 ]; then

        whiptail \
            --title "Operation Successful" \
            --scrolltext \
            --textbox "$OUTPUT_FILE" \
            32 110

    else

        whiptail \
            --title "Operation Failed" \
            --scrolltext \
            --textbox "$OUTPUT_FILE" \
            32 110

    fi

    rm -f "$RAW_OUTPUT" "$OUTPUT_FILE"
}

########################################
# Deploy Release
########################################

deploy_release() {

    ENV=$(whiptail \
        --title "Deployment" \
        --inputbox \
        "Enter environment:

Allowed:
dev
staging
prod" \
        15 70 \
        "dev" \
        3>&1 1>&2 2>&3)

    [ $? -ne 0 ] && return

    VERSION=$(whiptail \
        --title "Deployment" \
        --inputbox \
        "Enter release version:

Example:
v1
v2" \
        15 70 \
        "v1" \
        3>&1 1>&2 2>&3)

    [ $? -ne 0 ] && return

    ########################################
    # Confirm
    ########################################

    if ! whiptail \
        --title "Confirm Deployment" \
        --yesno \
        "Environment : $ENV

Version     : $VERSION

Start deployment?" \
        14 65
    then
        return
    fi

    ########################################
    # Deployment output
    ########################################

    OUTPUT_FILE="/tmp/config-deploy-deployment.log"

    rm -f "$AI_EVIDENCE"

    if "$DEPLOY" "$ENV" "$VERSION" >"$OUTPUT_FILE" 2>&1; then
        DEPLOY_RESULT=0
    else
        DEPLOY_RESULT=$?
    fi

    ########################################
    # Determine current state
    ########################################

    CURRENT=$(readlink -f "$BASE_DIR/current" 2>/dev/null || echo "unknown")

    PREVIOUS=$(readlink -f "$BASE_DIR/previous" 2>/dev/null || echo "unknown")

    ########################################
    # Successful Deployment
    ########################################

    if [ "$DEPLOY_RESULT" -eq 0 ]; then

        STATUS="SUCCESS"
        HEALTH_STATUS="PASSED"
        ROLLBACK_STATUS="NOT REQUIRED"

        RESULT_MESSAGE="
Environment : $ENV
Version     : $VERSION

Status      : SUCCESS
Health      : PASSED
Rollback    : NOT REQUIRED

Active Release:
$CURRENT
"

    ########################################
    # Failed Deployment
    ########################################

    else

        STATUS="FAILED"

        ####################################
        # Health status
        ####################################

        if grep -qi "health check failed" "$OUTPUT_FILE"; then
            HEALTH_STATUS="FAILED"
        else
            HEALTH_STATUS="UNKNOWN"
        fi

        ####################################
        # Rollback status
        ####################################

        if grep -qiE \
            "automatic rollback successful|rollback successful|rollback completed" \
            "$OUTPUT_FILE"
        then
            ROLLBACK_STATUS="SUCCESS"

        elif [ "$CURRENT" = "$PREVIOUS" ] && [ "$CURRENT" != "unknown" ]; then
            ROLLBACK_STATUS="SUCCESS"

        else
            ROLLBACK_STATUS="FAILED / NOT PERFORMED"
        fi

        ####################################
        # AI status
        ####################################

        if [ -f "$AI_EVIDENCE" ]; then
            AI_STATUS="AVAILABLE"
        else
            AI_STATUS="NOT AVAILABLE"
        fi

        RESULT_MESSAGE="
Environment : $ENV
Version     : $VERSION

Status      : FAILED
Health      : $HEALTH_STATUS
Rollback    : $ROLLBACK_STATUS
AI          : $AI_STATUS

Current Release:
$CURRENT

Previous Release:
$PREVIOUS
"

    fi

    ########################################
    # Show Deployment Result
    ########################################

    whiptail \
        --title "DEPLOYMENT RESULT" \
        --msgbox "$RESULT_MESSAGE" \
        22 75

    ########################################
    # Failed deployment options
    ########################################

    if [ "$DEPLOY_RESULT" -ne 0 ]; then

        while true; do

            FAILURE_OPTION=$(whiptail \
                --title "Deployment Failed" \
                --menu \
                "Deployment failed.

Choose an option:" \
                15 70 4 \
                "1" "View deployment log" \
                "2" "View AI diagnosis" \
                "3" "View current release" \
                "4" "Back to main menu" \
                3>&1 1>&2 2>&3)

            OPTION_STATUS=$?

            [ "$OPTION_STATUS" -ne 0 ] && break

            case "$FAILURE_OPTION" in

                1)

                    if [ -f "$OUTPUT_FILE" ]; then

                        whiptail \
                            --title "Deployment Details" \
                            --scrolltext \
                            --textbox "$OUTPUT_FILE" \
                            32 110

                    else

                        message "Deployment log is not available."

                    fi
                    ;;

                2)

                    ai_diagnosis
                    ;;

                3)

                    CURRENT=$(readlink -f "$BASE_DIR/current" 2>/dev/null || echo "unknown")

                    whiptail \
                        --title "Current Release" \
                        --msgbox \
"Current active release:

$CURRENT" \
                        12 75
                    ;;

                4)
                    break
                    ;;

            esac

        done

    fi

    rm -f "$OUTPUT_FILE"
}

########################################
# Rollback
########################################

rollback_release() {

    if ! whiptail \
        --title "Rollback" \
        --yesno \
        "Are you sure you want to rollback

to the previous release?" \
        12 65
    then
        return
    fi

    run_command "$ROLLBACK"
}

########################################
# Health Check
########################################

health_check() {

    run_command "$HEALTH"
}

########################################
# AI Failure Diagnosis
########################################

ai_diagnosis() {

    ####################################
    # Check evidence
    ####################################

    if [ ! -f "$AI_EVIDENCE" ]; then

        whiptail \
            --title "AI Failure Diagnosis" \
            --msgbox \
" No deployment failure evidence is available.

AI diagnosis is normally generated after
a deployment or health-check failure.

Run a deployment failure test first." \
            15 75

        return
    fi

    ####################################
    # Check AI script
    ####################################

    if [ ! -x "$AI" ]; then

        whiptail \
            --title "AI Failure Diagnosis" \
            --msgbox \
"AI diagnosis script is not executable:

$AI

Run:

chmod +x $AI" \
            14 75

        return
    fi

    ####################################
    # AI output
    ####################################

    AI_OUTPUT="/tmp/config-deploy-ai-output.log"

    ####################################
    # Processing message
    ####################################

    whiptail \
        --title "AI Failure Diagnosis" \
        --infobox \
"Analyzing deployment evidence...

Local AI:
llama3.2:3b

Please wait..." \
        10 65

    ####################################
    # Run AI
    ####################################

    if "$AI" "$AI_EVIDENCE" >"$AI_OUTPUT" 2>&1; then
        AI_RESULT=0
    else
        AI_RESULT=$?
    fi

    ####################################
    # Remove ANSI escape sequences
    ####################################

    CLEAN_OUTPUT="/tmp/config-deploy-ai-clean.log"

    sed -E 's/\x1B\[[0-9;?]*[ -\/]*[@-~]//g' \
        "$AI_OUTPUT" > "$CLEAN_OUTPUT"

    mv "$CLEAN_OUTPUT" "$AI_OUTPUT"

    ####################################
    # Display AI diagnosis
    ####################################

    if [ "$AI_RESULT" -eq 0 ]; then

        whiptail \
            --title "AI DEPLOYMENT DIAGNOSIS" \
            --scrolltext \
            --textbox "$AI_OUTPUT" \
            32 110

    else

        whiptail \
            --title "AI DIAGNOSIS ERROR" \
            --scrolltext \
            --textbox "$AI_OUTPUT" \
            32 110

    fi

    ####################################
    # Cleanup
    ####################################

    rm -f "$AI_OUTPUT"
}

########################################
# View Deployment Log
########################################

view_logs() {

    if [ ! -f "$LOG" ]; then

        message "Deployment log not found:

$LOG"

        return
    fi

    whiptail \
        --title "Deployment Logs" \
        --scrolltext \
        --textbox "$LOG" \
        32 110
}

########################################
# Main Menu
########################################

main_menu() {

    while true; do

        OPTION=$(whiptail \
            --title "NGINX ZERO-DOWNTIME DEPLOYMENT" \
            --menu \
"Linux Deployment Management

Select an operation:" \
            18 75 6 \
            "1" "Deploy Release" \
            "2" "Rollback Release" \
            "3" "Health Check" \
            "4" "AI Failure Diagnosis" \
            "5" "View Deployment Logs" \
            "6" "Exit" \
            3>&1 1>&2 2>&3)

        MENU_STATUS=$?

        [ "$MENU_STATUS" -ne 0 ] && break

        case "$OPTION" in

            1)
                deploy_release
                ;;

            2)
                rollback_release
                ;;

            3)
                health_check
                ;;

            4)
                ai_diagnosis
                ;;

            5)
                view_logs
                ;;

            6)
                break
                ;;

        esac

    done
}

########################################
# Start UI
########################################

main_menu
