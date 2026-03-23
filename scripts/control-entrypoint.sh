#!/bin/bash
# Fix SSH private key permissions after Docker bind mount.
# Host filesystems (Windows/Mac) may not preserve Unix file modes.
if [ -f /root/.ssh/id_rsa ]; then
  chmod 600 /root/.ssh/id_rsa
fi

exec "$@"
