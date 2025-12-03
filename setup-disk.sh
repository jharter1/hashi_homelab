#!/bin/bash
set -e

# Check if sda1 exists
if [ -b "/dev/sda1" ]; then
  echo "sda1 already exists"
  exit 0
fi

echo "Partitioning /dev/sda..."
# Partition sda using fdisk (create one primary partition)
# n: new partition
# p: primary
# 1: partition number
# default: first sector
# default: last sector
# w: write changes
echo -e "n\np\n1\n\n\nw" | fdisk /dev/sda

echo "Formatting /dev/sda1..."
# Format sda1
mkfs.ext4 -F /dev/sda1

# Create mount point
mkdir -p /data

echo "Mounting /dev/sda1 to /data..."
# Mount sda1
mount /dev/sda1 /data

# Add to fstab
echo "/dev/sda1 /data ext4 defaults 0 0" >> /etc/fstab

echo "Stopping services..."
# Stop services
systemctl stop nomad docker

# Prepare directories
mkdir -p /data/nomad /data/docker

echo "Moving data..."
# Move existing data
if [ -d "/opt/nomad" ]; then
  cp -a /opt/nomad/. /data/nomad/
  rm -rf /opt/nomad/*
else
  mkdir -p /opt/nomad
fi

if [ -d "/var/lib/docker" ]; then
  cp -a /var/lib/docker/. /data/docker/
  rm -rf /var/lib/docker/*
else
  mkdir -p /var/lib/docker
fi

echo "Creating bind mounts..."
# Bind mounts
mount --bind /data/nomad /opt/nomad
mount --bind /data/docker /var/lib/docker

# Add bind mounts to fstab
echo "/data/nomad /opt/nomad none bind 0 0" >> /etc/fstab
echo "/data/docker /var/lib/docker none bind 0 0" >> /etc/fstab

echo "Restarting services..."
# Restart services
systemctl start docker
systemctl start nomad

echo "Disk setup complete."
