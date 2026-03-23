# Implementation Plan — DART Ansible Orchestration

## Context

On-premise servers (app-server-N) run a DART data acquisition script for renewable energy plants.
Each server runs the same Docker image on a cron every 10 minutes (collect and exit).
Ansible is the deployment orchestrator. GitHub Actions is the CI/CD control node (no dedicated on-premise Ansible host).

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
              ├── docker pull ghcr.io/org/dart:latest   ← fetches new image from GHCR
              ├── docker compose down
              └── docker compose up                      ← runs with newly pulled image
```

Cron on each server continues independently every 10 min using whatever image is already local.

## First-time server setup

```
# 1. Add server to inventories/production/hosts.ini
# 2. Add host_vars/app-server-N.yml with healthcheck URL
# 3. Run:
make setup-prod   # or workflow_dispatch → setup
```

## Project structure changes

```
roles/
├── docker/           NEW — install Docker CE + docker compose plugin + GHCR login
├── dart-collector/   NEW — deploy compose file, create cron, verify cron health
└── dart-deploy/      NEW — docker pull + compose down/up

playbooks/
├── setup.yml         NEW — first-time server provisioning (docker + dart-collector)
└── deploy.yml        NEW — image update on all servers (dart-deploy)

inventories/production/
├── hosts.ini              UPDATE — add [app_servers] group
├── group_vars/all.yml     UPDATE — add GHCR image vars
└── host_vars/             NEW — per-server vars (healthcheck URL, etc.)

.github/workflows/
└── deploy.yml             UPDATE — add build job before Ansible deploy job
```

## GitHub Actions secrets required

| Secret | Used for |
|---|---|
| `PROD_SSH_PRIVATE_KEY` | SSH access to app-servers |
| `SSH_USER` | Remote user on app-servers |
| `GHCR_TOKEN` | Push image (Actions) + pull image (servers via Ansible) |
| `GHCR_USER` | GHCR username |
| `HEALTHCHECK_URL` | Default ping URL (overridable per host in host_vars) |
