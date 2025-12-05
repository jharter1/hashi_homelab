#!/bin/bash

# Setup Prometheus host volume on Nomad clients
# This script creates the required directory and configures it for Nomad

set -e

VOLUME_PATH="/mnt/prometheus_data"

echo "Setting up Prometheus host volume at $VOLUME_PATH..."

# Create directory with proper permissions
sudo mkdir -p "$VOLUME_PATH"
sudo chmod 777 "$VOLUME_PATH"

# Verify
ls -la "$VOLUME_PATH"
echo "✓ Prometheus volume ready at $VOLUME_PATH"
