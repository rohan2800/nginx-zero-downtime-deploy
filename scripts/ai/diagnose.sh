#!/bin/bash

set -euo pipefail

########################################
# Arguments
########################################

LOG_FILE="${1:-}"

MODEL="llama3.2:3b"

########################################
# Validation
########################################

if [ -z "$LOG_FILE" ]; then
    echo "Usage: diagnose.sh <log-file>"
    exit 1
fi

if [ ! -f "$LOG_FILE" ]; then
    echo "ERROR: Log file not found: $LOG_FILE"
    exit 1
fi

if ! command -v ollama >/dev/null 2>&1; then
    echo "ERROR: Ollama is not installed"
    exit 1
fi

########################################
# Build AI prompt
########################################

PROMPT=$(cat <<EOF
You are a Linux SRE analyzing a failed NGINX deployment.

IMPORTANT RULES:

- Analyze ONLY the evidence provided below.
- Do not invent facts.
- Do not assume information that is not present.
- Do not execute commands.
- Do not suggest destructive commands.
- If the evidence is insufficient, explicitly say "Insufficient evidence".
- Keep each section concise.
- Return ONLY the following five sections.

FORMAT:

ROOT CAUSE:
<one or two concise sentences>

EVIDENCE:
<specific evidence from the logs>

SEVERITY:
<LOW | MEDIUM | HIGH>

RECOMMENDED ACTION:
<safe corrective action>

ROLLBACK:
<YES | NO>
Reason: <one concise sentence>

DEPLOYMENT EVIDENCE:

$(cat "$LOG_FILE")
EOF
)

########################################
# Header
########################################

echo "========================================"
echo "AI DEPLOYMENT DIAGNOSIS"
echo "========================================"
echo

########################################
# Run AI
########################################

ollama run "$MODEL" "$PROMPT" 2>&1 |
sed -E 's/\x1B\[[0-9;?]*[ -\/]*[@-~]//g'
