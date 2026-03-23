# Ansible PoC — DART Deployment Orchestration

Ansible-based orchestration for deploying the DART data acquisition script to on-premise servers.
Everything runs inside Docker containers — the only requirement on the host machine is **Docker Desktop** and **make**.
No bash, no Python, no SSH client, no Ansible installation needed on the host.

## Architecture

### Production flow (GitHub Actions)

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
  host machine (any OS — only needs Docker Desktop)
  └── make <command>
          │
          ▼
┌───────────────────────────────────────────────────────┐
│                     Docker network                    │
│                                                       │
│  ┌──────────────────┐                                 │
│  │  ansible-control  │──SSH:22──► app-server-01       │
│  │  (Ansible + SSH)  │──SSH:22──► app-server-02       │
│  └──────────────────┘                                 │
│                                                       │
│  All commands run inside ansible-control.             │
│  Nothing executes directly on the host.               │
└───────────────────────────────────────────────────────┘
```

## Project structure

```
ansible-poc/
├── Dockerfile.control               # Ansible control node (Python + Ansible + SSH client)
├── Dockerfile.ssh-host              # Managed node (Ubuntu + SSH server)
├── docker-compose.yml               # ansible-control + app-server-01 + app-server-02
├── ansible.cfg                      # Ansible config (defaults to local inventory)
├── requirements.yml                 # Ansible collection dependencies (community.docker)
├── Makefile                         # All commands — runs everything via Docker
├── inventories/
│   ├── local/                       # Docker containers (used for testing)
│   │   ├── hosts.ini
│   │   └── group_vars/all.yml
│   └── production/                  # On-premise servers (real IPs)
│       ├── hosts.ini
│       ├── group_vars/all.yml
│       └── host_vars/               # Per-server overrides (e.g. healthcheck URL)
├── playbooks/
│   ├── setup.yml                    # First-time server provisioning
│   ├── deploy.yml                   # Image update (docker pull + restart)
│   └── ping.yml                     # SSH connectivity check
├── roles/
│   ├── common/                      # Base packages, timezone, app directories
│   ├── docker/                      # Install Docker CE + login to GHCR
│   ├── dart-collector/              # Deploy compose file + create cron job
│   └── dart-deploy/                 # docker pull + compose down/up + verify cron
└── .github/workflows/
    └── deploy.yml                   # Build image → push GHCR → Ansible deploy
```

## Quick start

> **Do not run `docker compose up` directly.** SSH keys must be generated first.
> Always start with `make setup`.

```bash
make setup        # generate SSH keys + build all Docker images
make up           # start managed node containers
make ping         # test SSH connectivity
make setup-local  # provision containers (create dirs, compose file, cron)
make deploy       # simulate deploy (verify cron is intact)
```

## Local development flow

### First time (one-off)

```
clone repo
    │
    ▼
make setup          # generate SSH keys + build Docker images
    │
    ▼
make up             # start app-server-01 and app-server-02
    │
    ▼
make ping           # validate SSH connectivity — must pass before anything else
    │
    ▼
make setup-local    # provision: create dirs, deploy compose file, create cron
```

### Development cycle (repeat for every change)

```
edit playbooks / roles / templates
    │
    ▼
make check          # dry-run — shows what would change, applies nothing
    │
    ├── looks wrong? ──► fix and repeat
    │
    ▼
make setup-local    # apply changes (idempotent — safe to re-run)
    or
make deploy         # test deploy flow (cron verification)
    │
    ├── something failed?
    │       │
    │       ▼
    │   make shell  # bash inside ansible-control for debugging
    │   make ping   # re-check connectivity
    │       │
    │       └──► fix and repeat
    │
    ▼
commit and push     # triggers GitHub Actions → build → deploy to production
```

### Cleanup

```bash
make down    # stop containers (keep SSH keys and images for next session)
make clean   # stop containers + delete SSH keys (full reset)
```

### Rebuilding after changes to Dockerfile or requirements.yml

```bash
make down
make setup   # rebuilds all images
make up
```

## What is tested locally vs production

| Task | Local | Production |
|---|---|---|
| SSH connectivity | yes | yes |
| Directory creation | yes | yes |
| Template deployment (docker-compose.yml) | yes | yes |
| Cron job creation and verification | yes | yes |
| Docker CE installation | skipped | yes |
| GHCR authentication | skipped | yes |
| Docker image pull | skipped | yes |
| Docker Compose restart | skipped | yes |

Docker-related tasks are guarded with `when: env != 'local'` because managed node containers don't run Docker inside them. Everything else is validated identically.

## Adding a new server

1. Add the server to `inventories/production/hosts.ini`:
   ```ini
   app-server-03 ansible_host=10.0.0.3
   ```

2. Create `inventories/production/host_vars/app-server-03.yml`:
   ```yaml
   ---
   healthcheck_url: https://hc-ping.com/your-uuid-here
   ```

3. Run first-time provisioning:
   ```bash
   make setup-prod
   ```

## CI/CD — GitHub Actions

The workflow at `.github/workflows/deploy.yml` triggers on every push to `main`.

### Pipeline

```
push → main
    │
    ▼
[build]   docker build + push to GHCR (:latest + :sha-xxx)
    │
    ▼
[deploy]  ansible-playbook deploy.yml → SSH → all app-servers
          environment: production (manual approval if configured)
```

### Manual trigger

`Actions → Build and Deploy → Run workflow` — choose `deploy` or `setup`.

### Required GitHub secrets

| Secret | Description |
|---|---|
| `PROD_SSH_PRIVATE_KEY` | Private SSH key for app-servers |
| `SSH_USER` | Remote user on app-servers |
| `GHCR_USER` | GitHub username for GHCR |
| `GHCR_TOKEN` | GitHub token with `packages:write` scope |
| `HEALTHCHECK_URL` | Default Healthcheck.io ping URL |

### Security

- SSH key and vault password exist on the runner only during the deploy step and are deleted in a cleanup that always runs, even on failure.
- No secrets are stored in the repository. All are injected at runtime via environment variables and Ansible `-e` flags.

## All make targets

| Target | Description |
|---|---|
| `make help` | List all available targets |
| `make setup` | Generate SSH keys + build Docker images |
| `make up` | Start managed node containers |
| `make down` | Stop and remove all containers |
| `make restart` | Restart all containers |
| `make ping` | Test SSH connectivity (local) |
| `make ping-prod` | Test SSH connectivity (production) |
| `make setup-local` | First-time provisioning (local) |
| `make setup-prod` | First-time provisioning (production) |
| `make deploy` | Simulate deploy (local) |
| `make deploy-prod` | Deploy to production |
| `make check` | Dry-run (local) |
| `make check-prod` | Dry-run (production) |
| `make shell` | Bash inside ansible-control |
| `make ssh-server-01` | SSH into app-server-01 |
| `make ssh-server-02` | SSH into app-server-02 |
| `make clean` | Remove containers + SSH keys |
