#!/usr/bin/env fish

# Script to populate local Docker registry with commonly used images
# This reduces pull times and avoids Docker Hub rate limits

set REGISTRY "registry.home:5000"

# List of commonly used images in your homelab
# Format: "source_image:tag local_name:tag"
set IMAGES \
    "traefik:v2.10" \
    "grafana/grafana:latest" \
    "prom/prometheus:latest" \
    "grafana/loki:latest" \
    "grafana/alloy:latest" \
    "louislam/uptime-kuma:latest" \
    "linuxserver/calibre-web:latest" \
    "linuxserver/code-server:latest" \
    "linuxserver/homepage:latest" \
    "minio/minio:latest" \
    "registry:2" \
    "consul:1.22.1" \
    "hashicorp/consul:1.22.1" \
    "alpine:latest" \
    "nginx:alpine" \
    "redis:alpine" \
    "postgres:16-alpine"

echo "Populating registry at $REGISTRY with commonly used images..."
echo ""

for image in $IMAGES
    echo "Processing $image..."
    
    # Pull from Docker Hub
    if docker pull $image
        # Tag for local registry
        set local_image "$REGISTRY/$image"
        docker tag $image $local_image
        
        # Push to local registry
        if docker push $local_image
            echo "✓ Successfully cached $image"
        else
            echo "✗ Failed to push $image to registry"
        end
    else
        echo "✗ Failed to pull $image from Docker Hub"
    end
    
    echo ""
end

echo "Registry population complete!"
echo ""
echo "View cached images: curl http://$REGISTRY/v2/_catalog"
