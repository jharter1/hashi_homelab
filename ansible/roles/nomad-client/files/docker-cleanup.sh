#!/bin/bash
# Clean up Docker images, containers, volumes
docker system prune -af --volumes

# Clean up old journal logs
journalctl --vacuum-size=100M

# Clean up old Nomad allocations
find /opt/nomad/alloc -type d -mtime +7 -exec rm -rf {} + 2>/dev/null || true
