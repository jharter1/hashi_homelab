#!/usr/bin/env bash
# Configure Docker to use the local registry as a pull-through cache

set -e

REGISTRY_HOST="${1:-registry.home:5000}"

echo "Configuring Docker to use registry mirror at $REGISTRY_HOST..."

# Backup existing daemon.json if it exists
if [ -f /etc/docker/daemon.json ]; then
    sudo cp /etc/docker/daemon.json /etc/docker/daemon.json.bak
    echo "Backed up existing /etc/docker/daemon.json"
fi

# Create or update daemon.json
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "registry-mirrors": ["http://$REGISTRY_HOST"],
  "insecure-registries": ["$REGISTRY_HOST"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2"
}
EOF

echo "Docker daemon configuration updated"
echo "Restarting Docker..."
sudo systemctl restart docker

echo "Waiting for Docker to start..."
sleep 3

if sudo systemctl is-active --quiet docker; then
    echo "✓ Docker is running"
    echo "✓ Registry mirror configured: http://$REGISTRY_HOST"
    echo ""
    echo "Testing registry connection..."
    if curl -s "http://$REGISTRY_HOST/v2/" > /dev/null 2>&1; then
        echo "✓ Registry is accessible"
    else
        echo "⚠ Warning: Could not reach registry at http://$REGISTRY_HOST/v2/"
    fi
else
    echo "✗ Docker failed to start"
    exit 1
fi
