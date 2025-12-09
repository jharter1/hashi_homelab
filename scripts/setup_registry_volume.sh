#!/usr/bin/env bash
# Setup script for Docker Registry volume on NAS

set -e

echo "Setting up Docker Registry volume on NAS..."

# Create the directory on NAS
sudo mkdir -p /mnt/nas/registry
sudo chmod 755 /mnt/nas/registry

echo "Docker Registry volume created at /mnt/nas/registry"
echo ""
echo "Now add this to your Nomad client configuration:"
echo ""
echo "client {"
echo "  host_volume \"registry_data\" {"
echo "    path      = \"/mnt/nas/registry\""
echo "    read_only = false"
echo "  }"
echo "}"
echo ""
echo "Then restart the Nomad client: sudo systemctl restart nomad"
