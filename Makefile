SHELL := /bin/bash
LOCAL_INV  := inventories/local/hosts.ini
PROD_INV   := inventories/production/hosts.ini
PLAYBOOKS  := playbooks

.PHONY: help setup up down restart ping ping-prod \
        setup-local setup-prod deploy deploy-prod \
        check check-prod \
        ssh-server-01 ssh-server-02 ssh-db1 clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

# ─── Local environment setup ──────────────────────────────────────────────────

setup: ## Generate SSH keys and build Docker images (local)
	@echo "==> Generating SSH keys..."
	@bash scripts/setup-ssh-keys.sh
	@echo "==> Building Docker images..."
	docker compose build

# ─── Docker lifecycle ─────────────────────────────────────────────────────────

up: ## Start local Docker containers
	docker compose up -d
	@echo "==> Waiting for SSH to be ready..."
	@sleep 3
	@docker compose ps

down: ## Stop and remove local containers
	docker compose down

restart: down up ## Restart local containers

# ─── Connectivity ─────────────────────────────────────────────────────────────

ping: ## Ping all local (Docker) app-servers
	ansible-playbook -i $(LOCAL_INV) $(PLAYBOOKS)/ping.yml

ping-prod: ## Ping all production app-servers
	ansible-playbook -i $(PROD_INV) $(PLAYBOOKS)/ping.yml

# ─── First-time provisioning ──────────────────────────────────────────────────

setup-local: ## Provision local Docker containers (install Docker, cron, compose)
	ansible-playbook -i $(LOCAL_INV) $(PLAYBOOKS)/setup.yml

setup-prod: ## Provision production servers for the first time
	ansible-playbook -i $(PROD_INV) $(PLAYBOOKS)/setup.yml \
		--private-key ~/.ssh/prod_id_rsa \
		-e "ansible_user=$$SSH_USER" \
		-e "ghcr_org=$$GHCR_ORG"

# ─── Deploy (image update) ────────────────────────────────────────────────────

deploy: ## Pull latest image and restart on local Docker containers
	ansible-playbook -i $(LOCAL_INV) $(PLAYBOOKS)/deploy.yml

deploy-prod: ## Pull latest image and restart on production servers
	ansible-playbook -i $(PROD_INV) $(PLAYBOOKS)/deploy.yml \
		--private-key ~/.ssh/prod_id_rsa \
		-e "ansible_user=$$SSH_USER" \
		-e "ghcr_org=$$GHCR_ORG"

# ─── Dry-run / check mode ─────────────────────────────────────────────────────

check: ## Dry-run setup against local environment
	ansible-playbook -i $(LOCAL_INV) $(PLAYBOOKS)/setup.yml --check --diff

check-prod: ## Dry-run setup against production
	ansible-playbook -i $(PROD_INV) $(PLAYBOOKS)/setup.yml --check --diff \
		--private-key ~/.ssh/prod_id_rsa \
		-e "ansible_user=$$SSH_USER"

# ─── SSH shortcuts ────────────────────────────────────────────────────────────

ssh-server-01: ## SSH into app-server-01 container
	ssh -i ssh_keys/id_rsa -p 2221 -o StrictHostKeyChecking=no ansible@localhost

ssh-server-02: ## SSH into app-server-02 container
	ssh -i ssh_keys/id_rsa -p 2222 -o StrictHostKeyChecking=no ansible@localhost

ssh-db1: ## SSH into db1 container
	ssh -i ssh_keys/id_rsa -p 2223 -o StrictHostKeyChecking=no ansible@localhost

# ─── Cleanup ──────────────────────────────────────────────────────────────────

clean: down ## Remove containers and generated SSH keys
	@echo "==> Removing SSH keys..."
	rm -rf ssh_keys/
	@echo "==> Done."
