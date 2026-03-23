#!/bin/bash
# Generate SSH key pair for Ansible to connect to Docker containers
set -euo pipefail

KEY_DIR="$(dirname "$0")/../ssh_keys"

if [ -f "$KEY_DIR/id_rsa" ]; then
  echo "SSH keys already exist at $KEY_DIR — skipping."
  exit 0
fi

mkdir -p "$KEY_DIR"
ssh-keygen -t rsa -b 4096 -f "$KEY_DIR/id_rsa" -N "" -C "ansible-poc-local"
chmod 600 "$KEY_DIR/id_rsa"
chmod 644 "$KEY_DIR/id_rsa.pub"

echo "SSH keys generated:"
echo "  Private: $KEY_DIR/id_rsa"
echo "  Public:  $KEY_DIR/id_rsa.pub"
