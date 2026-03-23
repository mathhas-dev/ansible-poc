# Ansible PoC — DART Deployment Orchestration

Ansible-based orchestration for deploying the DART data acquisition script to on-premise servers.
Everything runs inside Docker containers. The only requirement on the host is **Docker Desktop**.

## Architecture

### Production flow (GitHub Actions)

```
git push → main
    │
    ▼
[build]   docker build → push ghcr.io/org/dart:latest
    │
    ▼
[deploy]  ansible-playbook deploy.yml  (SSH → all app-servers)
              ├── docker pull ghcr.io/org/dart:latest
              ├── docker compose down
              └── docker compose up

Each server — cron every 10 min:
    docker compose up → collect data → exit → ping Healthcheck.io
```

### Local environment

```
  host machine (any OS — only needs Docker Desktop)
  └── docker compose run --rm ansible-control <command>
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
│  Ansible, SSH, and all tasks run inside containers.   │
│  Only the docker CLI runs on the host.                │
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

```bash
# 1. Build all images
docker compose build

# 2. Generate SSH keys (run once)
docker compose run --rm ansible-control init

# 3. Start managed node containers
docker compose up -d app-server-01 app-server-02

# 4. Test SSH connectivity
docker compose run --rm ansible-control ping

# 5. Provision containers (create dirs, compose file, cron)
docker compose run --rm ansible-control setup-local

# 6. Simulate a deploy (verify cron is intact)
docker compose run --rm ansible-control deploy
```

## Local development flow

### First time (one-off)

```
clone repo
    │
    ▼
docker compose build                                   # build images
    │
    ▼
docker compose run --rm ansible-control init           # generate SSH keys
    │
    ▼
docker compose up -d app-server-01 app-server-02       # start managed nodes
    │
    ▼
docker compose run --rm ansible-control ping           # validate connectivity
    │
    ▼
docker compose run --rm ansible-control setup-local    # provision
```

### Development cycle (repeat for every change)

```
edit playbooks / roles / templates
    │
    ▼
docker compose run --rm ansible-control check          # dry-run
    │
    ├── looks wrong? ──► fix and repeat
    │
    ▼
docker compose run --rm ansible-control setup-local    # apply changes
    or
docker compose run --rm ansible-control deploy         # test deploy flow
    │
    ├── something failed?
    │       │
    │       ▼
    │   docker compose run --rm ansible-control shell   # debug
    │   docker compose run --rm ansible-control ping    # re-check connectivity
    │       │
    │       └──► fix and repeat
    │
    ▼
commit and push     # triggers GitHub Actions → build → deploy to production
```

### Cleanup

```bash
docker compose down                                    # stop containers

# Full reset (remove SSH keys — will need init again):
docker compose down
docker run --rm -v "./ssh_keys:/ssh_keys" alpine sh -c "rm -rf /ssh_keys/*"
```

### Rebuilding after changes to Dockerfile or requirements.yml

```bash
docker compose down
docker compose build
docker compose up -d app-server-01 app-server-02
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
   docker compose run --rm ansible-control setup-prod -e "ansible_user=deploy"
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

- SSH key exists on the runner only during the deploy step and is deleted in a cleanup that always runs.
- No secrets are stored in the repository. All are injected at runtime via environment variables.

## All commands

```bash
docker compose run --rm ansible-control help
```

| Command | Description |
|---|---|
| `init` | Generate SSH keys (run once before anything else) |
| `ping` | Test SSH connectivity (local) |
| `check` | Dry-run setup (local) |
| `setup-local` | Provision containers (local) |
| `deploy` | Simulate deploy (local) |
| `ping-prod` | Test SSH connectivity (production) |
| `check-prod` | Dry-run setup (production) |
| `setup-prod` | Provision servers (production) |
| `deploy-prod` | Deploy to production |
| `shell` | Bash inside control node |
| `ssh-server-01` | SSH into app-server-01 |
| `ssh-server-02` | SSH into app-server-02 |

Production commands accept extra Ansible flags:
```bash
docker compose run --rm ansible-control setup-prod -e "ansible_user=deploy" -e "ghcr_org=myorg"
```
