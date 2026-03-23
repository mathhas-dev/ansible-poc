# Ansible PoC — DART Deployment Orchestration

Ansible-based orchestration for deploying the DART data acquisition script to on-premise servers.
Docker containers are used locally to validate playbooks before touching production.

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

## Project structure

```
ansible-poc/
├── Dockerfile.ssh-host              # Base Ubuntu image with SSH (local testing)
├── docker-compose.yml               # Local containers: app-server-01, app-server-02, db1
├── ansible.cfg                      # Global Ansible config
├── Makefile                         # Shortcut commands
├── PLAN.md                          # Architecture decisions and design plan
├── inventories/
│   ├── local/                       # Docker inventory (localhost:222x)
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

## Quick start (local)

```bash
# 1. Generate SSH keys and build Docker images
make setup

# 2. Start containers
make up

# 3. Test SSH connectivity
make ping

# 4. First-time provisioning (installs Docker, cron, compose file)
make setup-local

# 5. Simulate a deploy (pull latest image + restart)
make deploy
```

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
