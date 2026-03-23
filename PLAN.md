# Implementation Plan — DART Ansible Orchestration

## Context

On-premise servers (app-server-N) run a DART data acquisition script for renewable energy plants.
Each server runs the same Docker image on a cron every 10 minutes (collect and exit).
Ansible is the deployment orchestrator. GitHub Actions is the CI/CD control node.
Everything runs inside Docker containers — the host only needs Docker Desktop.

## Responsibilities

| Actor | Responsibility |
|---|---|
| GitHub Actions (build job) | Build Docker image → push to GHCR |
| GitHub Actions (deploy job) | Run Ansible over SSH to all app-servers |
| Ansible `setup.yml` | First-time server: install Docker, authenticate GHCR, deploy compose file, create cron |
| Ansible `deploy.yml` | Subsequent deploys: `docker pull` → `compose down` → `compose up` |
| Cron (on each server) | Every 10 min: `docker compose up` → collect → exit → ping Healthcheck.io |

## Deploy flow

```
git push → main
    │
    ▼
[build]   docker build → push ghcr.io/org/dart:latest
    │
    ▼
[deploy]  ansible-playbook deploy.yml  (SSH → all app-servers in parallel)
              ├── docker pull ghcr.io/org/dart:latest
              ├── docker compose down
              └── docker compose up
```

Cron on each server continues independently every 10 min using whatever image is already local.

## Local testing

Everything runs inside Docker containers via the Makefile:

- `ansible-control`: Ansible control node (Python + Ansible + SSH client)
- `app-server-01`, `app-server-02`: Simulated managed nodes (Ubuntu + SSH server)

Docker-related tasks (install, pull, compose) are guarded with `when: env != 'local'` because
managed node containers don't run Docker inside them. All other tasks (dirs, templates, cron) run identically.

## Adding a new production server

1. Add to `inventories/production/hosts.ini`
2. Create `inventories/production/host_vars/<hostname>.yml` with healthcheck URL
3. Run `make setup-prod` or trigger GitHub Actions workflow with `setup` playbook

## GitHub Actions secrets

| Secret | Used for |
|---|---|
| `PROD_SSH_PRIVATE_KEY` | SSH access to app-servers |
| `SSH_USER` | Remote user on app-servers |
| `GHCR_USER` | GHCR authentication (push + pull) |
| `GHCR_TOKEN` | GHCR authentication (push + pull) |
| `HEALTHCHECK_URL` | Default ping URL |
