#!/bin/bash
# Copy SSH public key from mounted directory and fix permissions.
# The directory mount avoids Docker creating an empty file/dir when keys
# don't exist yet (e.g. before init runs).
set -e

if [ -f /tmp/ssh_keys/id_rsa.pub ]; then
  cp /tmp/ssh_keys/id_rsa.pub /home/ansible/.ssh/authorized_keys
  chmod 600 /home/ansible/.ssh/authorized_keys
  chown ansible:ansible /home/ansible/.ssh/authorized_keys
fi

exec /usr/sbin/sshd -D
