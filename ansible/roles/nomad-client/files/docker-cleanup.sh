#!/bin/bash
# Docker and system cleanup for Nomad clients
# Usage: docker-cleanup.sh [threshold%]
# Runs via cron: daily at 2AM (threshold 70%), hourly at :30 (threshold 85%)

DISK_THRESHOLD="${1:-70}"
LOGFILE=/var/log/docker-cleanup.log

USAGE=$(df / | awk 'NR==2 {print $5}' | tr -d '%')

if [ "$USAGE" -lt "$DISK_THRESHOLD" ]; then
  echo "$(date): disk at ${USAGE}% — below ${DISK_THRESHOLD}% threshold, skipping" >> "$LOGFILE"
  exit 0
fi

echo "$(date): disk at ${USAGE}% — running cleanup (threshold ${DISK_THRESHOLD}%)" >> "$LOGFILE"

# Prune unused images (NOT --volumes — safer for Nomad bind-mount volumes)
docker image prune -af >> "$LOGFILE" 2>&1

# Prune stopped containers (Nomad-managed containers that have exited)
docker container prune -f >> "$LOGFILE" 2>&1

# Trim journal logs
journalctl --vacuum-size=100M >> "$LOGFILE" 2>&1

AFTER=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
echo "$(date): cleanup done — disk now at ${AFTER}%" >> "$LOGFILE"
