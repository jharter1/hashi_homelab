# Docker Registry Setup Guide

## 1. Setup the Volume on NAS

The registry uses your existing NAS mount at `/mnt/nas/`. On each Nomad client node (10.0.0.60, 10.0.0.61, 10.0.0.62), create the registry directory:

```bash
sudo mkdir -p /mnt/nas/registry
sudo chmod 755 /mnt/nas/registry
```

## 2. Add Volume to Nomad Client Config

Add this to your Nomad client configuration (e.g., in your Terraform templates or `/etc/nomad.d/nomad.hcl`):

```hcl
client {
  host_volume "registry_data" {
    path      = "/mnt/nas/registry"
    read_only = false
  }
}
```

Then restart Nomad:

```bash
sudo systemctl restart nomad
```

## 3. Deploy the Registry

```bash
nomad job run jobs/services/docker-registry.nomad.hcl
```

## 4. Configure Docker to Use the Registry

On each node that will pull from the registry, configure Docker to use it as a mirror:

Edit `/etc/docker/daemon.json`:

```json
{
  "registry-mirrors": ["http://registry.home:5000"],
  "insecure-registries": ["registry.home:5000", "10.0.0.60:5000", "10.0.0.61:5000", "10.0.0.62:5000"]
}
```

Restart Docker:
```bash
sudo systemctl restart docker
```

**Note:** For production, you should set up TLS certificates. For a homelab, insecure registry is fine.

## 5. Usage

### Pull-Through Cache (Automatic)
Once configured, Docker will automatically cache images:

```bash
docker pull grafana/grafana:latest
# First pull: downloads from Docker Hub and caches
# Second pull: uses cached version from local registry
```

### Push Your Own Images
```bash
# Tag your image
docker tag myapp:latest registry.home:5000/myapp:latest

# Push to local registry
docker push registry.home:5000/myapp:latest

# Pull from local registry
docker pull registry.home:5000/myapp:latest
```

### In Nomad Jobs
Images will automatically be pulled from cache when available:

```hcl
config {
  image = "grafana/grafana:latest"  # Will use cache if available
}
```

## 6. Access the Web UI

Navigate to: `http://registry-ui.home`

You can browse cached images, view tags, and manage the registry.

## 7. Clean Up Old Images

List images:
```bash
curl -X GET http://registry.home:5000/v2/_catalog
```

Delete an image (requires DELETE enabled in config):
```bash
curl -X DELETE http://registry.home:5000/v2/<name>/manifests/<digest>
```

## Troubleshooting

### Check registry logs
```bash
nomad alloc logs -f <alloc-id> registry
```

### Test registry connectivity
```bash
curl http://registry.home:5000/v2/
# Should return: {}
```

### Check what's cached
```bash
curl http://registry.home:5000/v2/_catalog
```
