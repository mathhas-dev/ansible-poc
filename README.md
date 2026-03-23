# Ansible PoC — DART Deployment Orchestration

Ansible-based orchestration for deploying the DART data acquisition script to on-premise servers.
Everything runs in Docker — the only requirement on the host machine is **Docker Desktop**.

## Architecture

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

Each server — cron every 10 min:
    docker compose up → collect data → exit → ping Healthcheck.io
```

### Local environment (Docker only)

```
┌─────────────────────────────────────────────┐
│              Docker network                 │
│                                             │
│  ┌─────────────────┐                        │
│  │  ansible-control │──SSH──► app-server-01 │
│  │  (Ansible + SSH) │──SSH──► app-server-02 │
│  └─────────────────┘                        │
└─────────────────────────────────────────────┘
         ▲
    make ping / make deploy / ...
    (runs docker compose run --rm ansible-control)
```

## Project structure

```
ansible-poc/
├── Dockerfile.control               # Ansible control node image
├── Dockerfile.ssh-host              # Managed node image (Ubuntu + SSH)
├── docker-compose.yml               # All containers: control + app-server-01/02 + db1
├── ansible.cfg                      # Global Ansible config
├── Makefile                         # Shortcut commands
├── requirements.yml                 # Ansible collections (community.docker)
├── PLAN.md                          # Architecture decisions and design plan
├── inventories/
│   ├── local/                       # Docker inventory (container hostnames)
│   │   ├── hosts.ini
│   │   └── group_vars/all.yml
│   └── production/                  # On-premise production servers
│       ├── hosts.ini
│       ├── group_vars/all.yml
│       └── host_vars/               # Per-server overrides (e.g. healthcheck URL)
│           ├── app-server-01.yml
│           └── app-server-02.yml
├── playbooks/                       # What Ansible does and on which hosts
│   ├── setup.yml                    # First-time server provisioning
│   ├── deploy.yml                   # Image update on all servers
│   └── ping.yml                     # Connectivity check
├── roles/                           # Reusable units of tasks grouped by responsibility
│   ├── docker/                      # Install Docker CE + GHCR login
│   ├── dart-collector/              # Deploy compose file + create cron
│   ├── dart-deploy/                 # docker pull + compose down/up + verify cron
│   └── common/                      # Base packages, timezone (PoC example)
└── .github/workflows/
    └── deploy.yml                   # Build image → push GHCR → Ansible deploy
```

## Quick start

> **Do not run `docker compose up` directly.** The containers depend on SSH keys
> that must be generated first. Always start with `make setup`.

```bash
# 1. Generate SSH keys and build all Docker images (required before anything else)
make setup

# 2. Start managed node containers
make up

# 3. Test SSH connectivity (runs Ansible inside the control container)
make ping

# 4. First-time provisioning (cron, compose file — skips Docker install locally)
make setup-local

# 5. Simulate a deploy (cron verification — skips Docker pull locally)
make deploy

# 6. Open a shell in the control node for debugging
make shell
```

## Local development flow

### First time (one-off)

```
clone repo
    │
    ▼
make setup          # generate SSH keys + build all Docker images
    │
    ▼
make up             # start app-server-01, app-server-02, db1
    │
    ▼
make ping           # validate SSH connectivity — must pass before anything else
    │
    ▼
make setup-local    # run setup.yml: create dirs, deploy compose file, create cron
```

### Development cycle (repeat for every change)

```
edit playbooks / roles / templates
    │
    ▼
make check          # dry-run — shows what would change without applying anything
    │
    ├── looks wrong? ──► fix and repeat
    │
    ▼
make setup-local    # apply setup changes (idempotent — safe to re-run)
    or
make deploy         # apply deploy changes (cron verification)
    │
    ├── something failed?
    │       │
    │       ▼
    │   make shell  # open bash inside ansible-control for manual debugging
    │   make ping   # re-check connectivity
    │       │
    │       └──► fix and repeat from top
    │
    ▼
commit and push     # triggers GitHub Actions → build → deploy to production
```

### Cleanup

```bash
make down    # stop containers, keep SSH keys and images
make clean   # stop containers + delete SSH keys (full reset)
```

### Rebuilding after changes to Dockerfile or requirements.yml

```bash
make down
docker compose build   # rebuild images
make up
```

## What is tested locally vs production

| Task | Local (Docker) | Production |
|---|---|---|
| SSH connectivity | yes | yes |
| Directory creation | yes | yes |
| Template deployment | yes | yes |
| Cron creation and verification | yes | yes |
| Docker installation | skipped | yes |
| GHCR login | skipped | yes |
| `docker pull` | skipped | yes |
| `docker compose` restart | skipped | yes |

Docker-related tasks are skipped locally because managed node containers don't run Docker inside them. They validate everything else identically.

## Adding a new server

1. Add the server to `inventories/production/hosts.ini`
2. Create `inventories/production/host_vars/<hostname>.yml` with its healthcheck URL
3. Run first-time provisioning:

```bash
make setup-prod
# or trigger manually via GitHub Actions → Run workflow → setup
```

## Recommended workflow

```
make check        # dry-run locally (no changes applied)
make setup-local  # provision local Docker containers
make deploy       # simulate image update locally
make ping-prod    # validate SSH to production
make check-prod   # dry-run against production
make setup-prod   # provision new production server (first time only)
make deploy-prod  # manual deploy to production
```

## CI/CD — GitHub Actions

The workflow at `.github/workflows/deploy.yml` runs on every push to `main`.

### Pipeline

```
push → main
    │
    ▼
[build]   docker build + push to GHCR
    │
    ▼
[deploy]  ansible-playbook deploy.yml → SSH → all app-servers
          environment: production (manual approval gate if configured)
```

### Manual trigger

From the GitHub Actions UI (`Actions → Build and Deploy → Run workflow`), choose:
- `deploy` — pull latest image and restart (default)
- `setup` — first-time provisioning for new servers

### Required secrets

Add these under `Settings → Secrets and variables → Actions`:

| Secret | Description |
|---|---|
| `PROD_SSH_PRIVATE_KEY` | Private SSH key to connect to app-servers |
| `SSH_USER` | Remote user on app-servers |
| `GHCR_USER` | GitHub username for GHCR authentication |
| `GHCR_TOKEN` | GitHub token with `packages:write` scope |
| `HEALTHCHECK_URL` | Default Healthcheck.io ping URL |

### Security notes

- SSH private key is written to the runner only for the deploy step and deleted in a cleanup that always runs, even on failure.
- Secrets are never stored in the repository — injected at runtime via environment variables and `-e` flags.

## Production

Edit `inventories/production/hosts.ini` with real IPs or hostnames.
Each server can override `healthcheck_url` in its `host_vars/<hostname>.yml` file.
