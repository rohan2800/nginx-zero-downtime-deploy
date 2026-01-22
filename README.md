### Zero-Downtime NGINX Configuration Deployment (Linux)

## Overview

This project implements a production-grade, Linux-native zero-downtime deployment system for NGINX configuration files.
It uses atomic symlink switching, configuration validation, environment-specific safety controls, health checks, and automatic rollback to ensure safe deployments without interrupting live traffic.

The system mirrors real-world DevOps / SRE deployment patterns used in production Linux environments

## Key Features

- Zero-downtime NGINX reloads
- Atomic symlink-based deployments
- Multi-environment support (dev, staging, prod)
- Environment-specific safety gates
- Pre-reload NGINX configuration validation
- HTTP health checks with auto-rollback
- Bash-based deployment engine
- Whiptail-based Terminal UI (TUI)
- Deployment audit logging

## Architecture

- NGINX always reads configuration from a current symlink.

/opt/config-deploy/
├── current -> releases/dev/v2
├── releases/
│   ├── dev/
│   │   └── v2/
│   │       └── app.conf
│   ├── staging/
│   └── prod/
├── scripts/
│   └── deploy.sh
├── ui/
│   └── menu.sh
├── logs/
└── audit/

## Architecture Diagram

                 ┌────────────┐
                 │   Operator │
                 │ (CLI / UI) │
                 └─────┬──────┘
                       │
                       ▼
              ┌───────────────────┐
              │  deploy.sh (Bash) │
              └─────┬─────────────┘
                    │
        ┌───────────┴────────────┐
        ▼                        ▼
┌─────────────────┐     ┌──────────────────┐
│ Validate Config │     │ Health Check     │
│  nginx -t       │     │ curl localhost   │
└────────┬────────┘     └────────┬─────────┘
         │                       │
         ▼                       ▼
┌──────────────────────────────────────────┐
│        Atomic Symlink Switch             │
│  current → releases/<env>/<version>      │
└────────┬─────────────────────────────────┘
         |   
         ▼
┌──────────────────┐
│ nginx reload     │
│ (zero downtime)  │
└──────────────────┘

## Why symlinks?

- Symlink switches are atomic on Linux
- Instant rollback capability
- No file copying during deployment
- Safe even under live traffic

## Deployment Flow

1) Select environment and version
2) Validate NGINX configuration (nginx -t)
3) Atomically switch the current symlink
4) Reload NGINX without dropping connections
5) Perform HTTP health check
6) Automatically rollback on failure
7) Log deployment result (audit trail)

## Usage

# CLI Deployment
--> ./scripts/deploy.sh dev v1

# Terminal UI (TUI)
--> ./ui/menu.sh

## Environments

| Environment | Port | Safety Controls      |
| ----------- | ---- | -------------------- |
| dev         | 8080 | Fast deploy          |
| staging     | 8081 | Validation           |
| prod        | 80   | Confirmation + delay |

## Safety Mechanisms

- Configuration validation before reload
- Environment-specific rules
- Automatic rollback on health-check failure
- Least-privilege sudo access for reload commands
- Deployment audit logging 

## Tech Stack

1) Linux
2) Bash
3) NGINX
4) systemd
5) curl
6) Whiptail
7) Git

## Why This Project Matters

- Demonstrates real Linux system design
- Shows understanding of zero-downtime deployment strategies
- Focuses on safety, observability, and rollback
- Avoids heavy abstractions to highlight core Linux skills
- Highly relevant for Linux Administrator and DevOps roles

# Example Commands

- readlink /opt/config-deploy/current
- nginx -t
- systemctl is-active nginx
- curl http://localhost:8080

## Author
Rohan Waghmare
Aspiring Linux / DevOps Engineer
