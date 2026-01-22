#!/bin/bash

CURRENT=$(readlink /opt/config-deploy/current)

whiptail --msgbox "Current Active Version:\n\n$CURRENT" 10 60
