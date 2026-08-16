# Architecture — NGINX Zero-Downtime Deployment System

## 1. Overview

The NGINX Zero-Downtime Deployment System is a Linux-first deployment framework designed around one core principle:

> Keep releases immutable and change the active release pointer instead of modifying the live application files in place.

The system combines Bash automation, NGINX, symbolic links, health checks, rollback logic, Whiptail, logging, and optional local AI-assisted incident diagnosis.

---

## 2. Architectural Goals

### Primary goals

1. Deploy versioned releases safely.
2. Avoid copying files directly into the live web root.
3. Validate NGINX configuration before declaring success.
4. Validate application availability after deployment.
5. Restore the previous release when validation fails.
6. Provide an operator-friendly terminal interface.
7. Preserve evidence for troubleshooting.
8. Use local AI to assist diagnosis without giving AI control of remediation.

### Non-goals

The project is not intended to be a full replacement for Kubernetes, a cloud deployment platform, or an enterprise CD system.

It is intentionally designed to demonstrate Linux and DevOps fundamentals.

---

## 3. High-Level Architecture

```text
                         OPERATOR
                            │
                            ▼
                  ┌───────────────────┐
                  │    Whiptail UI    │
                  │    scripts/ui.sh  │
                  └─────────┬─────────┘
                            │
            ┌───────────────┼────────────────┐
            │               │                │
            ▼               ▼                ▼
        Deploy          Rollback         Health Check
            │               │                │
            └───────────────┼────────────────┘
                            ▼
                  ┌───────────────────┐
                  │  Deployment Core  │
                  │ scripts/deploy.sh │
                  └─────────┬─────────┘
                            │
                            ▼
                  Release Validation
                            │
                            ▼
              /opt/config-deploy/releases
                            │
                            ▼
                    Atomic Symlink
                            │
                            ▼
                  /opt/config-deploy/current
                            │
                            ▼
                    /var/www/app
                            │
                            ▼
                         NGINX
                            │
                            ▼
                       HTTP Client
                            │
                            ▼
                     Health Check
                       /       \
                     PASS      FAIL
                      │          │
                      ▼          ▼
                   SUCCESS    ROLLBACK
                                  │
                                  ▼
                         Previous Release
                                  │
                                  ▼
                         Failure Evidence
                                  │
                                  ▼
                       AI Diagnosis Script
                                  │
                                  ▼
                           Ollama / Llama
```

---

## 4. Directory Architecture

Runtime root:

```text
/opt/config-deploy
```

Recommended layout:

```text
/opt/config-deploy/
│
├── releases/
│   ├── dev/
│   │   ├── v1/
│   │   │   └── site/
│   │   │       └── index.html
│   │   └── v2/
│   │       └── site/
│   │           └── index.html
│   │
│   ├── staging/
│   └── prod/
│
├── current -> releases/<env>/<version>
├── previous -> releases/<env>/<previous-version>
│
├── scripts/
│   ├── deploy.sh
│   ├── rollback.sh
│   ├── health_check.sh
│   ├── ui.sh
│   └── ai/
│       └── diagnose.sh
│
├── logs/
│   └── deploy.log
│
└── audit/
    └── deploy.log
```

The Git repository contains the source and release examples. Runtime logs and generated state should not be committed.

---

## 5. Release Model

Each release is stored as an independent directory:

```text
releases/dev/v1/
releases/dev/v2/
```

A release contains the complete website/application artifact required by NGINX.

For example:

```text
releases/dev/v1/site/index.html
releases/dev/v2/site/index.html
```

This creates an immutable-style release model.

The system does not need to overwrite v1 when deploying v2.

---

## 6. Symlink-Based Activation

The active release is represented by:

```text
/opt/config-deploy/current
```

Example:

```text
current -> /opt/config-deploy/releases/dev/v2
```

The NGINX web root is connected to:

```text
/var/www/app -> /opt/config-deploy/current/site
```

Therefore:

```text
NGINX
  │
  ▼
/var/www/app
  │
  ▼
/opt/config-deploy/current/site
  │
  ▼
/opt/config-deploy/releases/dev/v2/site
```

When v1 is active:

```text
current -> releases/dev/v1
```

When v2 is active:

```text
current -> releases/dev/v2
```

The application path remains stable while the release target changes.

---

## 7. Why Symlinks?

A conventional deployment might do:

```text
copy new files
overwrite existing files
restart/reload service
```

That creates a risk of a partially updated application.

This project instead uses:

```text
release v1
release v2
    │
    ▼
current -> v2
```

The deployment changes the pointer rather than updating hundreds of files in place.

This reduces the deployment's mutation surface and makes rollback simple.

---

## 8. Deployment Lifecycle

### Step 1 — Input

The operator supplies:

```text
environment
version
```

Example:

```bash
deploy.sh dev v2
```

---

### Step 2 — Release Validation

The script checks that:

```text
/opt/config-deploy/releases/dev/v2
```

exists.

If it does not exist:

```text
Deployment aborted
```

No active release is changed.

---

### Step 3 — Capture Previous Release

Before switching:

```text
current -> v1
```

the current target is recorded as the previous release.

Conceptually:

```text
previous -> v1
```

This gives rollback a known target.

---

### Step 4 — Atomic Release Switch

The active pointer changes:

```text
current -> v1
```

to:

```text
current -> v2
```

The web root follows the current release.

---

### Step 5 — NGINX Configuration Validation

The deployment runs:

```bash
nginx -t
```

If configuration validation fails:

```text
v2
 ↓
validation failure
 ↓
restore v1
```

The deployment does not continue to a successful state.

---

### Step 6 — NGINX Reload

If validation passes:

```bash
systemctl reload nginx
```

A reload is preferred to a full service stop/start because NGINX can reload its configuration while continuing to serve existing connections.

---

### Step 7 — Health Check

The health-check script verifies that the application responds correctly.

Conceptually:

```text
HTTP request
     │
     ▼
NGINX
     │
     ▼
Application
     │
     ▼
Expected response
```

A failed health check means the release is not considered healthy.

---

### Step 8 — Automatic Rollback

On a failed deployment:

```text
current -> failed release
             │
             ▼
         health fail
             │
             ▼
       rollback.sh
             │
             ▼
current -> previous release
```

The previous release becomes active again.

---

## 9. Rollback Architecture

Rollback is intentionally simple.

The system keeps a pointer to the previous known release:

```text
previous -> v1
```

If the current deployment fails:

```text
current -> v2
previous -> v1
```

rollback changes the active state back to:

```text
current -> v1
```

This is considerably simpler than reconstructing a release from individual files.

---

## 10. Health Check as a Deployment Gate

The health check is not just monitoring.

It acts as a **deployment acceptance gate**.

```text
Deploy
  │
  ▼
NGINX validation
  │
  ▼
Reload
  │
  ▼
Health check
  │
  ├── PASS ──► SUCCESS
  │
  └── FAIL ──► ROLLBACK
```

This creates a clear definition of deployment success.

---

## 11. AI Failure Diagnosis Architecture

AI is deliberately isolated from the deployment control plane.

```text
Deployment Failure
        │
        ▼
Evidence Collection
        │
        ▼
/tmp/config-deploy-ai-evidence.log
        │
        ▼
scripts/ai/diagnose.sh
        │
        ▼
Ollama
        │
        ▼
llama3.2:3b
        │
        ▼
Structured Diagnosis
```

The expected diagnosis contains:

```text
ROOT CAUSE
EVIDENCE
SEVERITY
RECOMMENDED ACTION
ROLLBACK
```

---

## 12. AI Safety Boundary

The AI does **not** execute commands.

It is an advisory component.

### Control plane

Deterministic Bash logic controls:

```text
deployment
NGINX validation
health check
rollback
```

### Intelligence layer

AI handles:

```text
log interpretation
failure explanation
recommended corrective action
incident summarization
```

This separation is intentional.

A model can produce an incorrect recommendation. It should therefore not be trusted with unrestricted privileged execution.

---

## 13. Whiptail UI Architecture

The Whiptail interface provides an operator layer over the Bash scripts.

```text
                  Main Menu
                      │
       ┌──────────────┼──────────────┐
       │              │              │
       ▼              ▼              ▼
    Deploy         Rollback      Health Check
       │              │              │
       └──────────────┼──────────────┘
                      │
                      ▼
              AI Failure Diagnosis
                      │
                      ▼
                Deployment Logs
```

The UI does not replace the deployment logic.

It calls the underlying scripts.

This separation keeps:

```text
presentation layer
```

separate from:

```text
deployment logic
```

---

## 14. Logging Architecture

Two logical logging purposes are used.

### Deployment log

```text
/opt/config-deploy/logs/deploy.log
```

Used for operational troubleshooting.

### Audit log

```text
/opt/config-deploy/audit/deploy.log
```

Used to record deployment outcomes such as:

```text
timestamp
user
environment
version
status
```

This separation makes operational logs and audit information easier to reason about.

---

## 15. Environment Model

The release hierarchy supports:

```text
dev
staging
prod
```

Example:

```text
releases/
├── dev/
│   ├── v1/
│   └── v2/
│
├── staging/
│   └── v1/
│
└── prod/
    └── v1/
```

The deployment command remains:

```bash
deploy.sh <environment> <version>
```

Examples:

```bash
deploy.sh dev v2
deploy.sh staging v1
deploy.sh prod v1
```

Production deployments can include additional controls such as explicit confirmation or restricted permissions.

---

## 16. Failure Scenarios

### Scenario A — Release does not exist

```text
deploy v3
   │
   ▼
release missing
   │
   ▼
abort
```

No active release is changed.

---

### Scenario B — NGINX configuration failure

```text
switch to v2
      │
      ▼
nginx -t fails
      │
      ▼
restore previous
      │
      ▼
reload NGINX
```

---

### Scenario C — Health check failure

```text
switch to v2
      │
      ▼
nginx -t passes
      │
      ▼
health check fails
      │
      ▼
rollback
      │
      ▼
v1 restored
```

---

### Scenario D — AI unavailable

```text
deployment failure
      │
      ▼
AI diagnosis requested
      │
      ▼
Ollama unavailable
      │
      ▼
AI unavailable
```

The deployment system must still operate without AI.

This is an important architectural property:

> AI is an optional diagnostic dependency, not a deployment dependency.

---

## 17. Security Model

The project uses privileged operations for tasks such as:

```text
NGINX configuration
systemctl reload
web-root symlink changes
```

Production deployment should therefore use:

- dedicated service accounts
- least-privilege sudo
- controlled ownership of deployment directories
- restricted script permissions
- no plaintext secrets
- protected log files
- input validation
- deployment locking
- authenticated administration

AI should never receive unrestricted `sudo` access.

---

## 18. Failure Recovery Properties

The design provides:

### Fast rollback

Rollback changes a symlink instead of rebuilding the release.

### Release isolation

v1 and v2 coexist independently.

### Stable web path

NGINX continues using:

```text
/var/www/app
```

while the underlying release changes.

### Deterministic validation

NGINX and health checks determine deployment success.

### Explainability

Failure evidence can be passed to the AI layer for diagnosis.

---

## 19. Current Architecture vs Production Architecture

### Current project

```text
Single Linux host
       │
       ├── NGINX
       ├── Release directories
       ├── Bash deployment scripts
       ├── Whiptail
       └── Ollama
```

### Possible production evolution

```text
Git
 │
 ▼
CI/CD
 │
 ▼
Artifact Repository
 │
 ▼
Deployment Controller
 │
 ├── Node 1 → NGINX
 ├── Node 2 → NGINX
 └── Node 3 → NGINX
 │
 ▼
Load Balancer
 │
 ▼
Users

Observability
 ├── Metrics
 ├── Logs
 └── Alerts

AI
 └── Incident Diagnosis
```

The current implementation intentionally stays simpler to demonstrate Linux fundamentals.

---

## 20. Design Decisions

### Bash instead of Python

Bash is appropriate for this project because it directly demonstrates:

- Linux commands
- filesystem operations
- exit codes
- process control
- systemd integration
- NGINX administration
- permissions
- shell scripting

### Symlink activation instead of file copying

Symlink switching gives a simple release/rollback mechanism and avoids modifying a live release in place.

### Health check after reload

A successful `nginx -t` only proves that the configuration is syntactically valid.

It does not prove that the application is serving correctly.

Therefore:

```text
nginx -t
```

and:

```text
health check
```

serve different purposes.

### AI as advisory layer

The AI can help reduce troubleshooting time without becoming a privileged automation engine.

---

## 21. Operational Sequence

Normal deployment:

```text
Operator
   ↓
Whiptail
   ↓
deploy.sh
   ↓
Validate release
   ↓
Capture previous
   ↓
Switch current
   ↓
nginx -t
   ↓
Reload NGINX
   ↓
Health check
   ↓
SUCCESS
```

Failure deployment:

```text
Operator
   ↓
Whiptail
   ↓
deploy.sh
   ↓
Switch release
   ↓
Validation / health check
   ↓
FAIL
   ↓
Rollback
   ↓
Previous release restored
   ↓
Evidence retained
   ↓
AI diagnosis available
```

---

## 22. Testing Strategy

### Syntax tests

```bash
bash -n scripts/deploy.sh
bash -n scripts/rollback.sh
bash -n scripts/health_check.sh
bash -n scripts/ui.sh
bash -n scripts/ai/diagnose.sh
```

### Deployment tests

- deploy v1
- deploy v2
- verify active symlink
- verify HTTP response

### Rollback tests

- activate v2
- simulate a failed validation/health check
- verify v1 is restored

### AI tests

- provide known failure evidence
- verify structured diagnosis
- verify UI scrolling
- verify behavior when Ollama is unavailable

---

## 23. Future Architecture

Possible improvements:

1. GitHub Actions or Jenkins CI/CD.
2. Terraform-based infrastructure.
3. AWS deployment.
4. Prometheus/Grafana monitoring.
5. Centralized logging.
6. Multi-node NGINX.
7. Artifact repository.
8. Deployment locking.
9. Signed artifacts.
10. Structured JSON AI output.
11. Incident history and failure correlation.
12. Automated test suites.

These additions should preserve the core principle:

```text
Deterministic deployment control
        +
AI-assisted diagnosis
```

rather than allowing AI to become an uncontrolled privileged executor.
