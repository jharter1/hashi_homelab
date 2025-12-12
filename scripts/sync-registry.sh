#!/usr/bin/env bash
# Jenkins pipeline script to sync Docker images to local registry
# This script queries Nomad for running jobs and mirrors their images

set -e

NOMAD_ADDR="${NOMAD_ADDR:-http://10.0.0.50:4646}"
REGISTRY="${REGISTRY:-registry.home:5000}"

echo "=== Docker Registry Sync ==="
echo "Nomad: $NOMAD_ADDR"
echo "Registry: $REGISTRY"
echo ""

# Get all running jobs from Nomad
jobs=$(curl -s "$NOMAD_ADDR/v1/jobs" | jq -r '.[].ID')

declare -A images_to_sync

# Extract images from each job
for job in $jobs; do
    echo "Checking job: $job"
    job_spec=$(curl -s "$NOMAD_ADDR/v1/job/$job")
    
    # Extract Docker images from job spec
    job_images=$(echo "$job_spec" | jq -r '
        .TaskGroups[]?.Tasks[]? | 
        select(.Driver == "docker") | 
        .Config.image // empty' 2>/dev/null || true)
    
    for image in $job_images; do
        if [ -n "$image" ] && [[ ! "$image" =~ ^$REGISTRY ]]; then
            images_to_sync["$image"]=1
        fi
    done
done

echo ""
echo "=== Images to sync: ${#images_to_sync[@]} ==="
echo ""

# Sync each unique image
for image in "${!images_to_sync[@]}"; do
    echo "Syncing: $image"
    
    # Pull from source
    if docker pull "$image"; then
        # Tag for local registry
        local_image="$REGISTRY/$image"
        docker tag "$image" "$local_image"
        
        # Push to local registry
        if docker push "$local_image"; then
            echo "✓ Synced: $image -> $local_image"
        else
            echo "✗ Failed to push: $local_image"
        fi
    else
        echo "✗ Failed to pull: $image"
    fi
    
    echo ""
done

echo "=== Sync complete ==="
echo ""
echo "Registry catalog:"
curl -s "http://$REGISTRY/v2/_catalog" | jq .
