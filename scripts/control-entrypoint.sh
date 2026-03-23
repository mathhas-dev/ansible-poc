#!/bin/bash
set -e

LOCAL_INV="inventories/local/hosts.ini"
PROD_INV="inventories/production/hosts.ini"

# Copy SSH key to expected location and fix permissions
setup_ssh() {
  if [ -f /ansible/ssh_keys/id_rsa ]; then
    mkdir -p /root/.ssh
    cp /ansible/ssh_keys/id_rsa /root/.ssh/id_rsa
    chmod 600 /root/.ssh/id_rsa
  fi
}

setup_ssh

case "${1:-help}" in
  init)
    echo "==> Generating SSH keys..."
    if [ ! -f /ansible/ssh_keys/id_rsa ]; then
      mkdir -p /ansible/ssh_keys
      ssh-keygen -t rsa -b 4096 -f /ansible/ssh_keys/id_rsa -N "" -C "ansible-poc-local"
      echo "==> Done."
    else
      echo "SSH keys already exist — skipping."
    fi
    ;;

  # ─── Local ──────────────────────────────────────────────
  ping)
    exec ansible-playbook -i "$LOCAL_INV" playbooks/ping.yml
    ;;
  check)
    exec ansible-playbook -i "$LOCAL_INV" playbooks/setup.yml --check --diff
    ;;
  setup-local)
    exec ansible-playbook -i "$LOCAL_INV" playbooks/setup.yml
    ;;
  deploy)
    exec ansible-playbook -i "$LOCAL_INV" playbooks/deploy.yml
    ;;

  # ─── Production ────────────────────────────────────────
  ping-prod)
    shift
    exec ansible-playbook -i "$PROD_INV" playbooks/ping.yml "$@"
    ;;
  check-prod)
    shift
    exec ansible-playbook -i "$PROD_INV" playbooks/setup.yml --check --diff "$@"
    ;;
  setup-prod)
    shift
    exec ansible-playbook -i "$PROD_INV" playbooks/setup.yml "$@"
    ;;
  deploy-prod)
    shift
    exec ansible-playbook -i "$PROD_INV" playbooks/deploy.yml "$@"
    ;;

  # ─── Shell / SSH ────────────────────────────────────────
  shell)
    exec bash
    ;;
  ssh-server-*)
    server="${1#ssh-}"
    exec ssh -i /root/.ssh/id_rsa -o StrictHostKeyChecking=no "ansible@${server}"
    ;;

  # ─── Help ───────────────────────────────────────────────
  help|--help|-h)
    cat <<'HELP'
Usage: docker compose run --rm ansible-control <command>

Local (Docker):
  init          Generate SSH keys (run once before anything else)
  ping          Test SSH connectivity
  check         Dry-run setup (no changes applied)
  setup-local   Provision containers (create dirs, compose file, cron)
  deploy        Simulate deploy (verify cron)

Production:
  ping-prod     Test SSH connectivity to production
  check-prod    Dry-run setup against production
  setup-prod    Provision production servers (first time)
  deploy-prod   Deploy to production

Shell / SSH:
  shell           Open bash inside control node
  ssh-server-01   SSH into app-server-01
  ssh-server-02   SSH into app-server-02

Production commands accept extra Ansible flags:
  docker compose run --rm ansible-control setup-prod -e "ansible_user=deploy"
HELP
    ;;

  # ─── Passthrough ────────────────────────────────────────
  *)
    exec "$@"
    ;;
esac
