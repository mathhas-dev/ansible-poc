SHELL        := /bin/bash
LOCAL_INV    := inventories/local/hosts.ini
PROD_INV     := inventories/production/hosts.ini
PLAYBOOKS    := playbooks
ANSIBLE      := docker compose run --rm ansible-control

.PHONY: help setup up down restart ping ping-prod \
        setup-local setup-prod deploy deploy-prod \
        check check-prod shell clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

# ─── Local environment setup ──────────────────────────────────────────────────

setup: ## Generate SSH keys and build all Docker images
	@echo "==> Generating SSH keys..."
	@mkdir -p ssh_keys
	@docker run --rm \
		-v "$(CURDIR)/ssh_keys:/ssh_keys" \
		ubuntu:22.04 bash -c \
		"apt-get install -qq -y openssh-client > /dev/null 2>&1 && \
		 if [ ! -f /ssh_keys/id_rsa ]; then \
		   ssh-keygen -t rsa -b 4096 -f /ssh_keys/id_rsa -N '' -C 'ansible-poc-local'; \
		 else \
		   echo 'SSH keys already exist — skipping.'; \
		 fi"
	@echo "==> Building Docker images..."
	docker compose build

# ─── Docker lifecycle ─────────────────────────────────────────────────────────

up: ## Start managed node containers
	docker compose up -d app-server-01 app-server-02 db1
	@echo "==> Waiting for SSH to be ready..."
	@sleep 3
	@docker compose ps

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

# ─── Shell access ─────────────────────────────────────────────────────────────

shell: ## Open a shell inside the Ansible control node
	$(ANSIBLE) bash

# ─── Cleanup ──────────────────────────────────────────────────────────────────

clean: down ## Remove all containers and generated SSH keys
	@echo "==> Removing SSH keys..."
	rm -rf ssh_keys/
	@echo "==> Done."
