LOCAL_INV    := inventories/local/hosts.ini
PROD_INV     := inventories/production/hosts.ini
PLAYBOOKS    := playbooks
ANSIBLE      := docker compose run --rm ansible-control
SSH_CONTROL  := docker compose run --rm -it ansible-control ssh \
                  -i /root/.ssh/id_rsa -o StrictHostKeyChecking=no

.PHONY: help setup up down restart ping ping-prod \
        setup-local setup-prod deploy deploy-prod \
        check check-prod shell \
        ssh-server-01 ssh-server-02 ssh-db1 clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

# ─── Local environment setup ──────────────────────────────────────────────────

setup: ## Generate SSH keys and build all Docker images
	docker run --rm \
		-v "$(CURDIR)/ssh_keys:/ssh_keys" \
		ubuntu:22.04 bash -c \
		"apt-get install -qq -y openssh-client > /dev/null 2>&1 && \
		 if [ ! -f /ssh_keys/id_rsa ]; then \
		   ssh-keygen -t rsa -b 4096 -f /ssh_keys/id_rsa -N '' -C 'ansible-poc-local'; \
		 else \
		   echo 'SSH keys already exist — skipping.'; \
		 fi"
	docker compose build

# ─── Docker lifecycle ─────────────────────────────────────────────────────────

up: ## Start managed node containers
	docker compose up -d app-server-01 app-server-02 db1
	docker compose run --rm ansible-control \
		bash -c "sleep 3 && echo '==> Containers ready.'"
	docker compose ps

down: ## Stop and remove all containers
	docker compose down

restart: down up ## Restart all containers

# ─── Connectivity ─────────────────────────────────────────────────────────────

ping: ## Ping all local (Docker) app-servers
	$(ANSIBLE) ansible-playbook -i $(LOCAL_INV) $(PLAYBOOKS)/ping.yml

ping-prod: ## Ping all production app-servers
	$(ANSIBLE) ansible-playbook -i $(PROD_INV) $(PLAYBOOKS)/ping.yml

# ─── First-time provisioning ──────────────────────────────────────────────────

setup-local: ## Provision local Docker containers (cron, compose file — skips Docker install)
	$(ANSIBLE) ansible-playbook -i $(LOCAL_INV) $(PLAYBOOKS)/setup.yml

setup-prod: ## Provision production servers for the first time
	$(ANSIBLE) ansible-playbook -i $(PROD_INV) $(PLAYBOOKS)/setup.yml \
		-e "ansible_user=$$SSH_USER" \
		-e "ghcr_org=$$GHCR_ORG"

# ─── Deploy (image update) ────────────────────────────────────────────────────

deploy: ## Simulate deploy locally (cron check — skips Docker pull)
	$(ANSIBLE) ansible-playbook -i $(LOCAL_INV) $(PLAYBOOKS)/deploy.yml

deploy-prod: ## Pull latest image and restart on production servers
	$(ANSIBLE) ansible-playbook -i $(PROD_INV) $(PLAYBOOKS)/deploy.yml \
		-e "ansible_user=$$SSH_USER" \
		-e "ghcr_org=$$GHCR_ORG"

# ─── Dry-run / check mode ─────────────────────────────────────────────────────

check: ## Dry-run setup against local environment
	$(ANSIBLE) ansible-playbook -i $(LOCAL_INV) $(PLAYBOOKS)/setup.yml --check --diff

check-prod: ## Dry-run setup against production
	$(ANSIBLE) ansible-playbook -i $(PROD_INV) $(PLAYBOOKS)/setup.yml --check --diff \
		-e "ansible_user=$$SSH_USER"

# ─── Shell / SSH access ───────────────────────────────────────────────────────

shell: ## Open a bash shell inside the Ansible control node
	$(ANSIBLE) bash

ssh-server-01: ## SSH into app-server-01 (via control container)
	$(SSH_CONTROL) ansible@app-server-01

ssh-server-02: ## SSH into app-server-02 (via control container)
	$(SSH_CONTROL) ansible@app-server-02

ssh-db1: ## SSH into db1 (via control container)
	$(SSH_CONTROL) ansible@db1

# ─── Cleanup ──────────────────────────────────────────────────────────────────

clean: down ## Remove all containers and generated SSH keys
	docker run --rm -v "$(CURDIR)/ssh_keys:/ssh_keys" alpine \
		sh -c "rm -rf /ssh_keys/*"
