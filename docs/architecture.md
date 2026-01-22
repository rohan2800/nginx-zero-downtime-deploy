## Architecture

# Zero-Downtime NGINX Configuration Deployment

1. Design Objective

The primary goal of this system is to deploy NGINX configuration changes without service downtime while maintaining deployment safety, auditability, and fast rollback.
The design avoids complex tooling and instead relies on core Linux primitives that are stable and production-proven.

2. Core Design Principles

2.1 Atomic Operations

Linux symlink updates are atomic.
This allows configuration switches to happen instantly without partial states.

2.2 Validation Before Activation

Configuration must be syntactically valid before being applied.
Invalid configurations must never reach a running service.

2.3 Fast Rollback

Rollback should be:
Automatic
Instant
Safe under live traffic

2.4 Environment Isolation

Each environment (dev, staging, prod) follows its own safety rules and health checks.

3. High-Level Architecture

NGINX always reads configuration from a single entry point:
A symlink named current.

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

Only the current symlink changes during deployment.
No files are copied or modified in place.

4. Deployment Workflow

Operator selects environment and version
Deployment script validates input
NGINX configuration is validated using nginx -t
current symlink is switched atomically
NGINX is reloaded (not restarted)
HTTP health check verifies service availability
Rollback is triggered automatically if validation fails
Deployment result is written to audit logs

5. Symlink Strategy

Why symlinks?
Atomic switch guarantees consistency
Instant rollback capability
Avoids partial writes
Minimal I/O during deployment

Example
ln -sfn /opt/config-deploy/releases/dev/v2 /opt/config-deploy/current

6. Reload vs Restart

systemctl reload nginx
Keeps existing connections alive
Applies new configuration safely
systemctl restart nginx
Drops active connections
Causes downtime

This system never uses restart during deployment.

7. Health Check Strategy

After reload, the system verifies application health by sending an HTTP request to a known endpoint.

Environment	Port
dev		8080
staging		8081
prod		80

Failure to receive a successful response triggers rollback.

8. Rollback Mechanism

Rollback occurs when:
NGINX config validation fails
Health check fails
Service reload fails

Rollback steps:
Restore previous symlink target
Reload NGINX
Log failure in audit file
Rollback is fully automated and does not require manual intervention.

9. Security Considerations

Deployment user does not have full root access
Limited sudo permissions for NGINX reload only
No in-place file edits
Configuration directories use strict permissions
Audit logs provide traceability

10. Observability & Auditing

Deployment logs:
Timestamp
User
Environment
Version
Status (SUCCESS / FAILED)

This ensures accountability and simplifies troubleshooting.

11. Why This Architecture Is Production-Ready

Uses proven Linux primitives
Simple and transparent
Easy to debug
Minimal moving parts
Scales across environments

This architecture reflects real-world Linux and DevOps deployment systems.

12. Possible Future Enhancements

CI/CD pipeline integration
Blue-Green deployments
Canary releases
Prometheus health checks
Slack / Email notifications
