#!/bin/bash

URL="http://localhost:8080"
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$URL")

if [ "$STATUS" != "200" ]; then
    exit 1
fi
