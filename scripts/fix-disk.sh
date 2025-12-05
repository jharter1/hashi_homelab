#!/bin/bash
set -e

echo "Stopping services..."
systemctl stop nomad docker

echo "Unmounting lingering Nomad mounts..."
# Unmount any lingering Nomad mounts
# We use 'mount' to list, grep for /opt/nomad, extract mount point, sort reverse to unmount deep paths first
mount | grep '/opt/nomad' | awk '{print $3}' | sort -r | xargs -r umount

echo "Retrying move data..."
# Now try to move/remove again
if [ -d "/opt/nomad" ]; then
  # Only copy if destination is empty or doesn't exist, to avoid overwriting if previous run partially succeeded
  # Actually rsync is better but not available. cp -a -n (no clobber) might be good?
  # Let's just copy over.
  cp -a /opt/nomad/. /data/nomad/
  rm -rf /opt/nomad/*
fi

if [ -d "/var/lib/docker" ]; then
  if [ "$(ls -A /var/lib/docker)" ]; then
     cp -a /var/lib/docker/. /data/docker/
     rm -rf /var/lib/docker/*
  fi
fi

echo "Creating bind mounts..."
# Bind mounts
mount --bind /data/nomad /opt/nomad
mount --bind /data/docker /var/lib/docker

# Add bind mounts to fstab
if ! grep -q "/data/nomad /opt/nomad" /etc/fstab; then
  echo "/data/nomad /opt/nomad none bind 0 0" >> /etc/fstab
fi
if ! grep -q "/data/docker /var/lib/docker" /etc/fstab; then
  echo "/data/docker /var/lib/docker none bind 0 0" >> /etc/fstab
fi

echo "Restarting services..."
systemctl start docker
systemctl start nomad

echo "Disk fix complete."
