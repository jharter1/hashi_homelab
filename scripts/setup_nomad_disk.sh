#!/bin/bash
set -e

# Stop Nomad
echo "Stopping Nomad..."
systemctl stop nomad

# Find the 40G disk (approx 42949672960 bytes)
# We look for a disk that is roughly 40GB (allow some variance)
DISK=$(lsblk -b -d -o NAME,SIZE | awk '$2 > 38000000000 && $2 < 45000000000 {print $1}')

if [ -z "$DISK" ]; then
  echo "No 40G disk found!"
  lsblk
  exit 1
fi

DEVICE="/dev/$DISK"
echo "Found 40G disk: $DEVICE"

# Check if it has partitions
PARTITION="${DEVICE}1"
if lsblk "$DEVICE" | grep -q "${DISK}1"; then
  echo "Partition $PARTITION exists."
else
  echo "Partitioning $DEVICE..."
  echo "type=83" | sfdisk "$DEVICE"
  # Wait for partition to be available
  sleep 2
  PARTITION="${DEVICE}1"
fi

# Check if formatted
if ! blkid "$PARTITION" | grep -q "ext4"; then
  echo "Formatting $PARTITION..."
  mkfs.ext4 "$PARTITION"
else
  echo "$PARTITION is already formatted."
fi

# Create mount point if not exists
mkdir -p /opt/nomad

# Backup existing data if directory is not empty and not a mountpoint
if [ "$(ls -A /opt/nomad)" ] && ! mountpoint -q /opt/nomad; then
   echo "Backing up existing /opt/nomad data..."
   mv /opt/nomad /opt/nomad.bak
   mkdir -p /opt/nomad
fi

# Add to fstab if not present
UUID=$(blkid -s UUID -o value "$PARTITION")
if ! grep -q "$UUID" /etc/fstab; then
  echo "Adding to fstab..."
  echo "UUID=$UUID /opt/nomad ext4 defaults 0 0" >> /etc/fstab
fi

# Mount
echo "Mounting..."
mount -a

# Restore data if we backed it up
if [ -d "/opt/nomad.bak" ]; then
    echo "Restoring data..."
    cp -a /opt/nomad.bak/* /opt/nomad/
    # Optional: remove backup
    # rm -rf /opt/nomad.bak
fi

# Fix permissions
echo "Fixing permissions..."
chown -R nomad:nomad /opt/nomad

# Start Nomad
echo "Starting Nomad..."
systemctl start nomad

echo "Done!"
