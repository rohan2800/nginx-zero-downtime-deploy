#!/bin/bash

BASE_DIR="/opt/config-deploy"
RELEASES="$BASE_DIR/releases/$ENV"

ENV=$(whiptail --title "Select Environment" \
--menu "Choose environment" 12 40 3 \
"dev" "Development" \
"staging" "Staging" \
"prod" "Production" \
3>&1 1>&2 2>&3)

[ $? -ne 0 ] && exit 0


ENV="dev"

VERSIONS=$(ls "$RELEASES" 2>/dev/null)

if [ -z "$VERSIONS" ]; then
    whiptail --msgbox "No releases found" 8 40
    exit 1
fi

MENU_ITEMS=()
for v in $VERSIONS; do
    MENU_ITEMS+=("$v" "Deploy version $v")
done

VERSION=$(whiptail --title "Select Version" \
    --menu "Choose version to deploy" 15 60 6 \
    "${MENU_ITEMS[@]}" \
    3>&1 1>&2 2>&3)

[ $? -ne 0 ] && exit 0

clear
"$BASE_DIR/scripts/deploy.sh" "$ENV" "$VERSION" | tee /tmp/deploy.out

whiptail --textbox /tmp/deploy.out 20 80
