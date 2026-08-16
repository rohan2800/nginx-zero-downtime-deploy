NGINX Zero-Downtime Deployment System

A Linux-based release deployment and rollback framework for NGINX static websites, built with Bash, NGINX, systemd, Whiptail, and local AI-assisted failure diagnosis.

The project demonstrates how a Linux/DevOps engineer can implement versioned releases, atomic switching, health validation, rollback, audit logging, an interactive terminal UI, and local AI troubleshooting without depending on a large external deployment platform.

Features

Versioned releases — deploy v1, v2, etc. independently.
Multi-environment structure — supports dev, staging, and prod.
Atomic release switching — the active release is selected through symlinks.
NGINX configuration validation — deployment validates NGINX before considering the change successful.
Health checks — verifies the application after deployment
Automatic rollback — failed deployments can restore the previous release.
Manual rollback — operators can explicitly return to the previous release
Whiptail UI — terminal-based deployment management.
Local AI diagnosis — Ollama + llama3.2:3b analyzes collected failure evidence.
Deployment and audit logging — operational events are recorded for troubleshooting and review.
Linux-first implementation — primarily Bash, filesystem operations, NGINX, and systemd.

Architecture

High-level flow:

                    ┌──────────────────────┐
                    │     Whiptail UI      │
                    │      scripts/ui.sh   │
                    └──────────┬───────────┘
                               │
                 ┌─────────────┼─────────────┐
                 │             │             │
                 ▼             ▼             ▼
              Deploy        Rollback      Health
                 │             │          Check
                 ▼             ▼             │
          ┌──────────────────────────────┐   │
          │        Release Manager       │   │
          │       scripts/deploy.sh      │   │
          └──────────────┬───────────────┘   │
                         │                   │
                         ▼                   │
               Versioned Release             │
             releases/<env>/<version>        │
                         │                   │
                         ▼                   │
                 Atomic Symlink              │
                  current -> vX              │
                         │                   │
                         ▼                   │
                     NGINX                   │
                         │                   │
                         ▼                   │
                    HTTP App                 │
                         │                   │
                         └───────┬───────────┘
                                 ▼
                           Health Check
                                 │
                     ┌───────────┴───────────┐
                     │                       │
                    PASS                   FAIL
                     │                       │
                     ▼                       ▼
                  Success              Rollback
                                             │
                                             ▼
                                      Previous Release
                                             │
                                             ▼
                                     Failure Evidence
                                             │
                                             ▼
                                      Local AI Diagnosis
                                             │
                                             ▼
                                      Ollama / Llama

See architecture.md for the detailed architecture, deployment lifecycle, failure handling, security considerations, and design decisions.

Project Structure

nginx-zero-downtime-deploy/
├── README.md
├── architecture.md
├── LICENSE
│
├── releases/
│   └── dev/
│       ├── v1/
│       │   └── site/
│       │       └── index.html
│       └── v2/
│           └── site/
│               └── index.html
│
└── scripts/
    ├── deploy.sh
    ├── rollback.sh
    ├── health_check.sh
    ├── ui.sh
    │
    └── ai/
        └── diagnose.sh

Runtime directories such as logs/ and audit/ are intentionally kept outside the source-controlled release artifacts or ignored through .gitignore.

How the Deployment Works

A release is stored separately from the currently active release:

/opt/config-deploy/releases/dev/v1
/opt/config-deploy/releases/dev/v2

The active release is represented by:

/opt/config-deploy/current

For example:
current -> /opt/config-deploy/releases/dev/v2

The web root is then connected to the active release:
/var/www/app -> /opt/config-deploy/current/site

This means a deployment changes the release pointer instead of copying application files over the live site.

Deployment Lifecycle

1. Operator selects environment and version
              ↓
2. Validate release exists
              ↓
3. Record previous release
              ↓
4. Switch active release atomically
              ↓
5. Validate NGINX configuration
              ↓
6. Reload NGINX
              ↓
7. Run health check
              ↓
       ┌──────┴──────┐
       │             │
     PASS           FAIL
       │             │
       ▼             ▼
   Deployment      Rollback
    SUCCESS          │
                     ▼
              Restore previous
                     │
                     ▼
              Collect evidence
                     │
                     ▼
                AI diagnosis

Installation / Lab Setup

This project is designed for a Linux environment such as Ubuntu.

Required software

Linux
Bash
NGINX
systemd
curl
Whiptail
Git
Ollama (optional, for AI diagnosis)

Example dependency installation:

sudo apt update
sudo apt install -y nginx curl whiptail git

For local AI diagnosis, install Ollama separately and make sure the configured model is available:
ollama list

The current AI script uses:
llama3.2:3b

Runtime Layout

The deployment runtime uses:

/opt/config-deploy/
├── releases/
│   ├── dev/
├── current -> releases/<env>/<version>
├── previous -> releases/<env>/<previous-version>
├── logs/
│   └── deploy.log
└── audit/
    └── deploy.log

The NGINX application path is:
/var/www/app

Deploy a Release

Direct CLI usage:
sudo /opt/config-deploy/scripts/deploy.sh dev v1

Example:
sudo /opt/config-deploy/scripts/deploy.sh dev v2

Verify the active release:
readlink -f /opt/config-deploy/current

Verify the website:
curl http://localhost:8080

Whiptail UI

Start the interactive interface:
cd /opt/config-deploy
./scripts/ui.sh

The UI provides:

1  Deploy Release
2  Rollback Release
3  Health Check
4  AI Failure Diagnosis
5  View Deployment Logs
6  Exit

This keeps common operational tasks accessible without requiring the operator to remember every script argument.

Rollback

Manual rollback:
sudo /opt/config-deploy/scripts/rollback.sh

The rollback mechanism restores the previous active release rather than rebuilding or copying the application.

Verify:
readlink -f /opt/config-deploy/current

Health Check

Run manually:
/opt/config-deploy/scripts/health_check.sh

The deployment workflow uses the health check as a post-deployment validation gate.

A deployment should only be considered successful when the release is active and the health check passes.

AI Failure Diagnosis

The AI feature is intentionally advisory.

Failure evidence is collected into:
/tmp/config-deploy-ai-evidence.log

The diagnosis script is:
/opt/config-deploy/scripts/ai/diagnose.sh

Example:
/opt/config-deploy/scripts/ai/diagnose.sh \
    /tmp/config-deploy-ai-evidence.log

The local model is:
llama3.2:3b

The AI is instructed to return:

ROOT CAUSE
EVIDENCE
SEVERITY
RECOMMENDED ACTION
ROLLBACK

Why AI is advisory

AI should not directly execute production remediation.

The deployment system remains deterministic:
Bash → validation → health check → rollback

AI provides:
evidence analysis → diagnosis → recommendation

This separation reduces the risk of an incorrect model response changing production state.

Logging and Audit

Operational deployment logs:
/opt/config-deploy/logs/deploy.log

Audit records:
/opt/config-deploy/audit/deploy.log

These are useful for:
troubleshooting
deployment history
rollback investigation
interview demonstrations
operational auditing
Security Considerations

This is a Linux deployment lab/project and should be hardened before production use.

Recommended production improvements include:

least-privilege sudo rules
dedicated deployment service account
restricted filesystem permissions
authenticated monitoring
secrets management
signed releases
immutable artifacts
centralized logging
systemd service isolation
NGINX security headers
TLS/HTTPS
stronger health checks
deployment locking to prevent concurrent deployments

The AI component should remain isolated from privileged command execution.

Limitations

This implementation intentionally stays focused on Linux fundamentals and deployment automation.

Current limitations include:

local filesystem-based release storage
single-host deployment model
basic HTTP health validation
local Ollama dependency for AI diagnosis
no distributed locking
no artifact repository
no multi-node NGINX cluster
no external secrets manage
no production-grade observability stack

These limitations are opportunities for future iterations.

Future Improvements

Potential next versions:

Infrastructure
Terraform-based infrastructure provisioning
AWS deployment
Load balancer integration
multiple NGINX nodes

CI/CD
GitHub Actions
Jenkins pipeline
automated testing
image/artifact versioning
security scanning with Trivy

Observability
Prometheus
Grafana
centralized logging
deployment metrics
alerting

AI
structured JSON diagnosis
confidence score
historical failure correlation
log summarization
retrieval from previous incidents
AI should remain a recommendation layer rather than an unrestricted execution agent.

DevOps Concepts Demonstrated

This project demonstrates practical understanding of:

Linux filesystem management

Bash scripting

process exit codes

permissions

symbolic links

atomic operations

NGINX

systemd

service reloads

health checks

rollback strategies

environment separation

release versioning

logging

audit trails

terminal UI design

local AI integration

Git/GitHub workflow

Example Deployment

Initial state:
current -> v1
website  -> Version 1

Deploy v2:
current -> v2
website  -> Version 2

If v2 fails health check:
current -> v1
website  -> Version 1

The key idea is that the system changes the release pointer, not the contents of the live application directory.

Author
Rohan Waghmare
DevOps / Cloud Engineering Portfolio Project
