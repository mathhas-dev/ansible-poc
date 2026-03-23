#!/bin/bash
# Fix authorized_keys permissions after Docker bind mount.
# On Windows Docker Desktop, mounted files lose correct ownership/mode,
# which causes sshd to reject the key.
set -e

if [ -f /tmp/authorized_keys_src ]; then
  cp /tmp/authorized_keys_src /home/ansible/.ssh/authorized_keys
  chmod 600 /home/ansible/.ssh/authorized_keys
  chown ansible:ansible /home/ansible/.ssh/authorized_keys
fi

exec /usr/sbin/sshd -D
