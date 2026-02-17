# Service Deployment & Configuration Guide

This guide covers deployment and configuration for specialized services in the homelab: network monitoring, photo management, VPN remote access, Docker registry, and SSL/TLS configuration.

## Table of Contents

1. [Speedtest & Immich Deployment](#speedtest--immich-deployment)
2. [Tailscale VPN Remote Access](#tailscale-vpn-remote-access)
3. [Docker Registry Setup](#docker-registry-setup)
4. [Traefik SSL Configuration](#traefik-ssl-configuration)

---

# Speedtest & Immich Deployment

Deploy Speedtest Tracker (network monitoring) and Immich (photo/video backup) services.

## Speedtest Tracker Overview

Automated internet speed testing with historical tracking:
- **Database**: SQLite (local storage)
- **Schedule**: Automatic tests every 6 hours
- **Resources**: 256 MB memory
- **Access**: `https://speedtest.lab.hartr.net`

## Immich Overview

Self-hosted photo and video backup solution with mobile apps:
- **Database**: PostgreSQL with pgvector extension
- **Cache**: Redis (port 6380)
- **ML Features**: Optional face detection, object recognition
- **Resources**: 2.1 GB total (server + ML + microservices)
- **Access**: `https://immich.lab.hartr.net`

## Prerequisites

- NAS mounted at `/mnt/nas/` on all Nomad clients
- PostgreSQL with pgvector extension (for Immich)
- Nomad client configuration access

## Deployment Steps

### 1. Create NAS Directories

On each Nomad client (10.0.0.60-65):

```bash
# Speedtest Tracker
sudo mkdir -p /mnt/nas/speedtest_data
sudo chown -R 1000:1000 /mnt/nas/speedtest_data

# Immich
sudo mkdir -p /mnt/nas/immich_data
sudo mkdir -p /mnt/nas/immich_postgres
sudo mkdir -p /mnt/nas/immich_model-cache
sudo chown -R 1000:1000 /mnt/nas/immich_data
sudo chown -R 999:999 /mnt/nas/immich_postgres
sudo chown -R 1000:1000 /mnt/nas/immich_model-cache
```

### 2. Configure Nomad Client Host Volumes

Add to `/etc/nomad.d/nomad.hcl` on all clients:

```hcl
client {
  host_volume "speedtest_data" {
    path      = "/mnt/nas/speedtest_data"
    read_only = false
  }

  host_volume "immich_data" {
    path      = "/mnt/nas/immich_data"
    read_only = false
  }

  host_volume "immich_postgres" {
    path      = "/mnt/nas/immich_postgres"
    read_only = false
  }

  host_volume "immich_model-cache" {
    path      = "/mnt/nas/immich_model-cache"
    read_only = false
  }
}
```

Restart Nomad on all clients:

```bash
sudo systemctl restart nomad
```

### 3. Deploy Services

```bash
# Speedtest Tracker
nomad job run jobs/services/speedtest.nomad.hcl

# Immich (includes server, ML, microservices, PostgreSQL, Redis)
nomad job run jobs/services/immich.nomad.hcl

# Check deployment status
nomad job status speedtest
nomad job status immich
```

## Service Details

### Speedtest Tracker Configuration

- **Testing interval**: Every 6 hours (configurable in job file)
- **Database**: SQLite at `/config/database.sqlite`
- **Web interface**: Modern UI with charts and historical data
- **Notifications**: Can be configured in-app for speed degradation alerts

**Default credentials** (change after first login):
- No authentication by default - configure in settings

### Immich Architecture

**Components**:
1. **Immich Server** (512 MB): Main API and web interface
2. **Immich Machine Learning** (768 MB): Face detection, object recognition
3. **Immich Microservices** (768 MB): Background jobs, thumbnail generation
4. **PostgreSQL** (256 MB): Database with pgvector for ML embeddings
5. **Redis** (128 MB): Job queue and caching

**Storage**:
- Photos/videos: `/mnt/nas/immich_data/upload/`
- Thumbnails: `/mnt/nas/immich_data/thumbs/`
- ML models: `/mnt/nas/immich_model-cache/`

## Troubleshooting

### Speedtest: Tests Not Running

**Symptoms**: Dashboard shows no recent tests.

**Solutions**:
1. Check container logs:
   ```bash
   nomad alloc logs -f <speedtest-alloc-id> speedtest
   ```

2. Verify SQLite database permissions:
   ```bash
   ssh ubuntu@<node> "ls -la /mnt/nas/speedtest_data/database.sqlite"
   ```
   Should be owned by UID 1000.

3. Manually trigger test via web UI: Settings → Run Test Now

### Speedtest: Database Locked Errors

**Symptoms**: "database is locked" errors in logs.

**Solution**: SQLite doesn't handle concurrent writes well on NFS. This is expected behavior. Tests will retry automatically.

### Immich: Upload Failures

**Symptoms**: Mobile app shows "Failed to upload" errors.

**Solutions**:
1. Check disk space:
   ```bash
   ssh ubuntu@<node> "df -h /mnt/nas"
   ```

2. Verify write permissions:
   ```bash
   ssh ubuntu@<node> "ls -la /mnt/nas/immich_data/"
   ```

3. Check server logs:
   ```bash
   nomad alloc logs -f <immich-alloc-id> immich-server
   ```

4. Verify PostgreSQL connection:
   ```bash
   nomad alloc logs <immich-alloc-id> immich-postgres
   ```

### Immich: ML Features Not Working

**Symptoms**: Face detection/object recognition not detecting anything.

**Solutions**:
1. Enable ML in Immich settings: Administration → Machine Learning → Enable

2. Check ML service logs:
   ```bash
   nomad alloc logs -f <immich-alloc-id> immich-machine-learning
   ```

3. Verify model cache directory:
   ```bash
   ssh ubuntu@<node> "ls -la /mnt/nas/immich_model-cache/"
   ```

4. Trigger ML job manually: Administration → Jobs → Run Face Detection

### Immich: Database Connection Refused

**Symptoms**: Immich server shows "Connection refused" to PostgreSQL.

**Solutions**:
1. Verify PostgreSQL is running in the same allocation:
   ```bash
   nomad alloc status <immich-alloc-id>
   ```
   Should show both `immich-server` and `immich-postgres` tasks.

2. Check PostgreSQL logs:
   ```bash
   nomad alloc logs <immich-alloc-id> immich-postgres
   ```

3. Verify Redis is running:
   ```bash
   nomad alloc logs <immich-alloc-id> immich-redis
   ```

## ML Features (Immich)

Immich includes powerful machine learning capabilities:

### Face Detection
- Automatically detects and groups faces
- Enable: Administration → Machine Learning → Face Detection
- Processes photos after upload (background job)

### Object Recognition (CLIP)
- Tags photos with detected objects/scenes
- Enable: Administration → Machine Learning → Smart Search
- Allows semantic search ("beach sunset", "dog in park")

### Duplicate Detection
- Finds visually similar or identical photos
- Configure threshold: Administration → Duplicate Detection
- Manual review before deletion

**Performance Notes**:
- ML processing is CPU-intensive (768 MB allocation)
- Initial processing of large libraries can take hours/days
- Models cached to `/mnt/nas/immich_model-cache/` (reused after restarts)

## Backup & Data Management

### Speedtest Data

**Database backup**:
```bash
# Copy SQLite database
scp ubuntu@<node>:/mnt/nas/speedtest_data/database.sqlite ./speedtest-backup-$(date +%Y%m%d).sqlite
```

**Restore**:
```bash
scp ./speedtest-backup-*.sqlite ubuntu@<node>:/mnt/nas/speedtest_data/database.sqlite
nomad job restart speedtest
```

### Immich Data

**Critical directories**:
- `/mnt/nas/immich_data/upload/` - Original photos/videos (most important)
- `/mnt/nas/immich_data/thumbs/` - Thumbnails (regenerable)
- `/mnt/nas/immich_postgres/` - PostgreSQL data (metadata, ML embeddings)

**Backup strategy**:

1. **Photos/videos** (use Immich's built-in tools):
   - Mobile app auto-backup
   - External library import (watch folder)

2. **Database**:
   ```bash
   # Backup PostgreSQL
   nomad alloc exec <immich-alloc-id> immich-postgres \
     pg_dump -U immich immich > immich-db-backup-$(date +%Y%m%d).sql
   ```

3. **Full NAS backup** (recommended):
   ```bash
   rsync -avz /mnt/nas/immich_data/ /backup/immich/
   ```

**Restore**:
```bash
# Stop Immich
nomad job stop immich

# Restore data
rsync -avz /backup/immich/ /mnt/nas/immich_data/

# Restore database
cat immich-db-backup-*.sql | nomad alloc exec -i <immich-alloc-id> immich-postgres \
  psql -U immich immich

# Restart
nomad job run jobs/services/immich.nomad.hcl
```

---

# Tailscale VPN Remote Access

Deploy Tailscale for secure remote access to your homelab from anywhere.

## Overview

Tailscale provides zero-config VPN access to your homelab network:

- **Deployment**: Single Nomad job on `nomad-client-1` (10.0.0.60)
- **Subnet routing**: Advertises entire `10.0.0.0/24` network
- **Authentication**: OAuth via Tailscale account
- **DNS**: Optional MagicDNS for easy service access
- **Access**: All homelab services accessible via VPN tunnel

## Architecture

```
Remote Device (phone/laptop) 
    ↓ (Tailscale VPN tunnel)
Tailscale Node (nomad-client-1) 
    ↓ (subnet routes: 10.0.0.0/24)
Entire Homelab Network
    ↓
All Services (Nomad, Consul, Vault, apps)
```

**Why only one node?**
- Only one node needs to advertise subnet routes
- Other clients connect to this gateway
- Reduces complexity and potential routing conflicts

## Prerequisites

- Tailscale account (free tier works)
- Nomad cluster with one designated gateway node (typically `nomad-client-1`)
- NAS storage for persistent Tailscale state
- Taskfile.yml configured

## Deployment Steps

### 1. Quick Start

```bash
# Deploy Tailscale to nomad-client-1
task tailscale:deploy

# Authenticate (visit URL in logs)
task tailscale:status
# Look for authentication URL: https://login.tailscale.com/a/...

# After authenticating in browser, approve subnet routes:
# Visit Tailscale admin panel → Machines → dev-nomad-client-1 → Edit route settings
# Enable: 10.0.0.0/24

# Verify connectivity
task tailscale:ip
```

### 2. Manual Deployment

If not using Taskfile:

```bash
# Deploy job
nomad job run jobs/services/tailscale.nomad.hcl

# Get authentication URL from logs
nomad alloc logs -f <alloc-id> tailscale

# Look for: "To authenticate, visit: https://login.tailscale.com/a/..."
# Open URL in browser and authenticate

# Approve subnet routes in Tailscale admin panel
```

### 3. Configure Traefik (Optional)

Deploy Tailscale-integrated Traefik for secure external access:

```bash
task tailscale:deploy:traefik
```

This configuration allows Traefik to be accessible via Tailscale IPs with proper authentication.

## DNS Configuration

Choose one of three DNS approaches:

### Option 1: MagicDNS + Global Nameserver (Recommended)

**Enable in Tailscale admin panel**:
1. DNS → Enable MagicDNS
2. Nameservers → Add: `10.0.0.30` (your homelab DNS server)

**Benefits**:
- Access services via Tailscale names: `dev-nomad-client-1`
- Homelab DNS resolves: `grafana.lab.hartr.net` → `10.0.0.60`
- Works from any Tailscale-connected device

**Example**:
```bash
# From remote device connected to Tailscale
curl https://grafana.lab.hartr.net  # Resolves via homelab DNS
ping dev-nomad-client-1             # Resolves via MagicDNS
```

### Option 2: DNS Override Configuration

**Enable in Tailscale admin panel**:
1. DNS → Add nameserver → Global nameservers
2. Add: `10.0.0.30` (your DNS server)
3. Override local DNS: ON

**Benefits**:
- All DNS queries routed through homelab DNS
- No split horizon DNS needed
- Simpler configuration than MagicDNS

**Drawbacks**:
- All DNS traffic goes through VPN (slight latency)
- May conflict with some split-tunnel configurations

### Option 3: Local Hosts File

**Edit on each remote device**:

```bash
# macOS/Linux: /etc/hosts
# Windows: C:\Windows\System32\drivers\etc\hosts

10.0.0.50 nomad.lab.hartr.net
10.0.0.60 grafana.lab.hartr.net traefik.lab.hartr.net
10.0.0.60 prometheus.lab.hartr.net
```

**Benefits**:
- No DNS configuration needed
- Works offline (with cached entries)
- Simple for small number of services

**Drawbacks**:
- Manual management on each device
- Doesn't scale for many services
- No dynamic updates

## Subnet Routing

### How It Works

1. Tailscale node on `nomad-client-1` advertises `10.0.0.0/24` routes
2. You approve routes in Tailscale admin panel
3. Connected devices route all `10.0.0.x` traffic through VPN
4. Access any homelab service by IP or DNS

### Approving Routes

**In Tailscale admin panel**:
1. Navigate to: Machines → `dev-nomad-client-1`
2. Click: Edit route settings
3. Enable: `10.0.0.0/24`
4. Click: Save

### Verification

From remote device connected to Tailscale:

```bash
# Test routing
ping 10.0.0.50  # Should reach Nomad server
ping 10.0.0.60  # Should reach Nomad client

# Test service access
curl http://10.0.0.50:4646/ui  # Nomad UI
curl https://grafana.lab.hartr.net  # Service via DNS
```

## Task Commands

Convenient Taskfile commands for Tailscale management:

```bash
# Deployment
task tailscale:deploy          # Deploy Tailscale job
task tailscale:deploy:traefik  # Deploy Traefik with Tailscale integration

# Status & Monitoring
task tailscale:status          # Show Tailscale status and peers
task tailscale:ip              # Show Tailscale IP address

# Manual operations
nomad job status tailscale     # Check job status
nomad alloc logs -f <alloc-id> # Follow logs for auth URL
```

## Troubleshooting

### Issue: Subnet Routes Not Working

**Symptoms**: Can't reach homelab IPs (`10.0.0.x`) from remote device.

**Solutions**:
1. Verify routes are approved in Tailscale admin panel
2. Check route advertisement in Tailscale status:
   ```bash
   # SSH to nomad-client-1
   ssh ubuntu@10.0.0.60
   docker exec <tailscale-container> tailscale status
   # Should show: "10.0.0.0/24 advertised"
   ```

3. Verify client routing table (on remote device):
   ```bash
   # macOS/Linux
   netstat -rn | grep 10.0.0
   # Should show route via Tailscale interface
   ```

4. Restart Tailscale client on remote device

### Issue: Services Not Accessible via HTTPS

**Symptoms**: HTTP works but HTTPS fails or shows certificate errors.

**Solutions**:
1. Verify you're using homelab DNS or hosts file with correct IPs
2. Check SSL certificate validity:
   ```bash
   openssl s_client -connect grafana.lab.hartr.net:443 -servername grafana.lab.hartr.net
   ```

3. Ensure Tailscale isn't intercepting HTTPS (disable HTTPS inspection if enabled)

4. For self-signed certs, add CA to device trust store

### Issue: Authentication URL Not Showing

**Symptoms**: Container starts but no authentication URL in logs.

**Solutions**:
1. Check if already authenticated:
   ```bash
   nomad alloc logs <alloc-id> tailscale | grep -i "logged in"
   ```

2. If already authenticated, no action needed

3. Force re-authentication:
   ```bash
   nomad job stop tailscale
   # Delete state directory on host
   ssh ubuntu@10.0.0.60 "sudo rm -rf /mnt/nas/tailscale_state/*"
   nomad job run jobs/services/tailscale.nomad.hcl
   ```

### Issue: DNS Not Resolving Homelab Services

**Symptoms**: Tailscale works but `grafana.lab.hartr.net` doesn't resolve.

**Solutions**:
1. **If using MagicDNS**: Verify global nameserver is set to `10.0.0.30`
2. **If using DNS override**: Check override is enabled in Tailscale settings
3. **If using hosts file**: Verify entries are correct
4. Test DNS directly:
   ```bash
   dig @10.0.0.30 grafana.lab.hartr.net
   # Should return 10.0.0.60
   ```

5. Check Tailscale DNS settings in admin panel

## Security Considerations

### Access Control Lists (ACLs)

**Define in Tailscale admin panel** (Access Controls → Edit ACLs):

```json
{
  "acls": [
    // Allow subnet routing from specific devices
    {
      "action": "accept",
      "src": ["your-laptop", "your-phone"],
      "dst": ["10.0.0.0/24:*"]
    },
    // Restrict sensitive ports
    {
      "action": "deny",
      "src": ["*"],
      "dst": ["10.0.0.0/24:22"]  // Block SSH except from specific devices
    }
  ]
}
```

### Traefik Authentication Middleware

For services exposed via Tailscale, add authentication:

```hcl
# In service tags
tags = [
  "traefik.enable=true",
  "traefik.http.routers.myservice.rule=Host(`myservice.lab.hartr.net`)",
  "traefik.http.routers.myservice.middlewares=auth@file",  // Add auth middleware
  "traefik.http.routers.myservice.entrypoints=websecure",
  "traefik.http.routers.myservice.tls=true",
]
```

### Best Practices

1. **Enable 2FA** on Tailscale account for added security
2. **Use ACLs** to restrict access to sensitive services
3. **Regular audits**: Review connected devices in Tailscale admin panel
4. **Dedicated gateway**: Only advertise routes from one trusted node
5. **Monitor access**: Check Tailscale logs for unusual connections
6. **Rotate keys**: Periodically re-authenticate nodes (revoke old keys)

### Network Isolation

**Consider firewall rules on nomad-client-1**:

```bash
# Example: Allow Tailscale, deny everything else to sensitive ports
sudo ufw allow from 100.64.0.0/10 to any port 22  # Tailscale CGNAT range
sudo ufw deny from any to any port 22             # Deny other SSH
```

## Advanced Configuration

### Split Tunneling

If you want some traffic to bypass VPN:

1. **In Tailscale client settings**: Disable "Use Tailscale DNS" for specific domains
2. **On device**: Configure routes to exclude certain networks

### Multiple Gateway Nodes

For redundancy, advertise routes from multiple nodes:

1. Deploy Tailscale to additional clients
2. Modify job constraint to pin to specific nodes
3. Approve all advertised routes in admin panel
4. Tailscale automatically load-balances

**Note**: Current configuration uses only `nomad-client-1` to avoid complexity.

---

# Docker Registry Setup

Deploy a private Docker registry with pull-through cache for faster image pulls and offline availability.

## Overview

Self-hosted Docker registry with two primary use cases:

1. **Pull-through cache**: Automatically cache images from Docker Hub
2. **Private registry**: Store and distribute custom/internal images

**Benefits**:
- Faster image pulls (local network speed)
- Reduced Docker Hub rate limiting
- Offline availability of cached images
- Private image hosting

**Components**:
- **Registry** (5000/tcp): Docker Distribution registry
- **Registry UI** (80/tcp): Web interface for browsing images
- **Storage**: NFS at `/mnt/nas/registry`

## Deployment Steps

### 1. Setup NAS Volume

On each Nomad client (10.0.0.60-65):

```bash
sudo mkdir -p /mnt/nas/registry
sudo chmod 755 /mnt/nas/registry
```

### 2. Add Volume to Nomad Client Config

Edit `/etc/nomad.d/nomad.hcl` on all clients:

```hcl
client {
  host_volume "registry_data" {
    path      = "/mnt/nas/registry"
    read_only = false
  }
}
```

Restart Nomad:

```bash
sudo systemctl restart nomad
```

### 3. Deploy the Registry

```bash
nomad job run jobs/services/docker-registry.nomad.hcl

# Verify deployment
nomad job status docker-registry
```

## Configure Docker Clients

On each node that will use the registry (all Nomad clients):

### 1. Edit Docker Daemon Config

Create or edit `/etc/docker/daemon.json`:

```json
{
  "registry-mirrors": ["http://registry.home:5000"],
  "insecure-registries": [
    "registry.home:5000",
    "10.0.0.60:5000",
    "10.0.0.61:5000",
    "10.0.0.62:5000"
  ]
}
```

**Explanation**:
- `registry-mirrors`: Docker automatically checks this registry before Docker Hub
- `insecure-registries`: Allow HTTP (no TLS) for homelab use

### 2. Restart Docker

```bash
sudo systemctl restart docker
```

**Note**: For production environments, configure TLS certificates instead of using insecure registries.

## Usage

### Pull-Through Cache (Automatic)

Once configured, Docker automatically caches images:

```bash
# First pull - downloads from Docker Hub and caches locally
docker pull grafana/grafana:latest

# Second pull - uses cached version (much faster)
docker pull grafana/grafana:latest
```

**How it works**:
1. Docker checks local cache
2. Docker checks registry mirror (`registry.home:5000`)
3. If not in mirror, registry pulls from Docker Hub and caches
4. Subsequent pulls use cached version

### Push Custom Images

Store your own images in the registry:

```bash
# Tag your image with registry prefix
docker tag myapp:latest registry.home:5000/myapp:latest

# Push to local registry
docker push registry.home:5000/myapp:latest

# Pull from local registry (from any node)
docker pull registry.home:5000/myapp:latest
```

### Using in Nomad Jobs

Images are automatically pulled from cache when available:

```hcl
task "app" {
  driver = "docker"
  
  config {
    image = "grafana/grafana:latest"  # Will use cache if available
  }
}
```

For custom images:

```hcl
task "app" {
  driver = "docker"
  
  config {
    image = "registry.home:5000/myapp:latest"  # Pull from private registry
  }
}
```

## Web UI Access

Browse cached images via web interface:

**URL**: `http://registry-ui.home`

**Features**:
- View all cached/stored images
- Browse image tags and layers
- View image metadata
- Delete images (if enabled)

## Management & Maintenance

### List Cached Images

```bash
curl -X GET http://registry.home:5000/v2/_catalog

# Pretty print with jq
curl -s http://registry.home:5000/v2/_catalog | jq .
```

**Example output**:
```json
{
  "repositories": [
    "grafana/grafana",
    "prom/prometheus",
    "myapp"
  ]
}
```

### List Image Tags

```bash
curl -X GET http://registry.home:5000/v2/grafana/grafana/tags/list

# Pretty print
curl -s http://registry.home:5000/v2/grafana/grafana/tags/list | jq .
```

### Delete Images

**Prerequisites**: Enable deletion in registry config (add to job file):

```hcl
env {
  REGISTRY_STORAGE_DELETE_ENABLED = "true"
}
```

**Delete image manifest**:

```bash
# Get image digest
DIGEST=$(curl -I -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
  http://registry.home:5000/v2/<image>/manifests/<tag> | \
  grep Docker-Content-Digest | awk '{print $2}' | tr -d '\r')

# Delete manifest
curl -X DELETE http://registry.home:5000/v2/<image>/manifests/$DIGEST
```

**Run garbage collection** (reclaim storage):

```bash
# Exec into registry container
nomad alloc exec -it <registry-alloc-id> registry /bin/sh

# Run garbage collection
registry garbage-collect /etc/docker/registry/config.yml
```

### Storage Management

**Check storage usage**:

```bash
ssh ubuntu@<node> "du -sh /mnt/nas/registry"
```

**Clear all cached images** (nuclear option):

```bash
nomad job stop docker-registry
ssh ubuntu@<node> "sudo rm -rf /mnt/nas/registry/*"
nomad job run jobs/services/docker-registry.nomad.hcl
```

## Troubleshooting

### Issue: Images Not Being Cached

**Symptoms**: Every pull still goes to Docker Hub.

**Solutions**:
1. Verify Docker daemon config:
   ```bash
   cat /etc/docker/daemon.json
   docker info | grep -A5 "Registry Mirrors"
   ```

2. Check registry is accessible:
   ```bash
   curl http://registry.home:5000/v2/
   # Should return: {}
   ```

3. Test manual pull:
   ```bash
   docker pull registry.home:5000/library/nginx:latest
   ```

4. Check registry logs:
   ```bash
   nomad alloc logs -f <registry-alloc-id> registry
   ```

### Issue: "x509: certificate signed by unknown authority"

**Symptoms**: TLS certificate errors when pulling images.

**Solution**: This is why we use `insecure-registries`. Verify it's configured:

```bash
docker info | grep "Insecure Registries"
```

Should list your registry IPs/hostnames.

**For production**: Generate proper TLS certificates and remove `insecure-registries` config.

### Issue: "pull access denied for registry.home:5000/..."

**Symptoms**: Permission denied when pulling from registry.

**Solutions**:
1. Verify image exists:
   ```bash
   curl http://registry.home:5000/v2/_catalog
   ```

2. Check image format - should be:
   - Official images: `registry.home:5000/library/<image>:<tag>`
   - Custom images: `registry.home:5000/<image>:<tag>`

3. For pull-through cache, ensure original image exists:
   ```bash
   docker pull nginx:latest  # Pull from Docker Hub first
   ```

### Issue: Registry Out of Storage

**Symptoms**: Push failures, allocation restarts, disk full errors.

**Solutions**:
1. Check NAS space:
   ```bash
   df -h /mnt/nas
   ```

2. Run garbage collection (see Management section above)

3. Delete unused images via API or UI

4. Consider storage quotas or automatic cleanup policies

### Check Registry Logs

```bash
# Get allocation ID
nomad job status docker-registry

# Follow logs
nomad alloc logs -f <alloc-id> registry

# Check for errors
nomad alloc logs <alloc-id> registry | grep -i error
```

## Security Considerations

### For Homelab (Current Config)

- **HTTP only**: Insecure registries for simplicity
- **No authentication**: Open to anyone on network
- **Network isolation**: Only accessible from homelab network

**Acceptable for**:
- Internal homelab use
- Isolated network
- Trusted users only

### For Production

**Enable TLS**:

```hcl
# In Nomad job file
env {
  REGISTRY_HTTP_TLS_CERTIFICATE = "/certs/domain.crt"
  REGISTRY_HTTP_TLS_KEY          = "/certs/domain.key"
}
```

**Enable authentication**:

```hcl
env {
  REGISTRY_AUTH                 = "htpasswd"
  REGISTRY_AUTH_HTPASSWD_PATH   = "/auth/htpasswd"
  REGISTRY_AUTH_HTPASSWD_REALM  = "Registry Realm"
}
```

**Use proper DNS**:
- Replace `registry.home:5000` with real domain
- Get Let's Encrypt certificate via Traefik

### Best Practices

1. **Regular backups**: Backup `/mnt/nas/registry` directory
2. **Monitor storage**: Set alerts for disk usage
3. **Audit access**: Enable logging and review periodically
4. **Rate limiting**: Configure if exposing externally
5. **Vulnerability scanning**: Scan cached images for CVEs

## Advanced: Registry as Artifactory Alternative

This registry can serve as a lightweight Artifactory replacement for Docker images:

**Features**:
- Pull-through caching (like Artifactory remote repositories)
- Private repository (like Artifactory local repositories)
- Web UI for browsing

**Missing vs Artifactory**:
- No built-in vulnerability scanning (use Clair or Trivy separately)
- No user management (single auth or none)
- No other artifact types (Helm, npm, etc. - would need separate registries)

**Good for**:
- Small teams
- Docker-only workflows
- Homelab/development environments

---

# Traefik SSL Configuration

Configure Traefik to automatically provision and manage SSL/TLS certificates via Let's Encrypt using DNS-01 challenge with AWS Route 53.

## Overview

Automated SSL certificate management for all homelab services using wildcard certificates.

### Architecture

```
User → Home DNS (*.lab.hartr.net → 10.0.0.60) → Traefik (6 nodes) → Consul → Services
                                                      ↓
                                         Let's Encrypt ← Route 53 (DNS-01)
```

**Components**:
- **Traefik**: System job on 6 Nomad clients (10.0.0.60-65)
- **Home DNS**: Points `*.lab.hartr.net` to 10.0.0.60 (primary endpoint)
- **Route 53**: Public DNS for Let's Encrypt validation
- **Consul**: Service discovery and health checking
- **Let's Encrypt**: Free SSL/TLS certificates using DNS-01 challenge
- **Shared ACME storage**: All Traefik instances use same `/opt/traefik/acme/` directory

### Traffic Flow

1. User accesses `https://grafana.lab.hartr.net` from home network
2. Home DNS resolves to 10.0.0.60
3. Request hits Traefik (running on 10.0.0.60 or any client)
4. Traefik queries Consul for service location
5. Consul returns healthy service instance
6. Traefik proxies request with SSL termination

### DNS-01 Challenge

**Why DNS-01?**
- Works behind NAT (no port forwarding needed)
- Allows wildcard certificates (`*.lab.hartr.net`)
- No need to expose port 80/443 to internet

**How it works**:
1. Let's Encrypt asks for TXT record: `_acme-challenge.lab.hartr.net`
2. Traefik creates TXT record in Route 53
3. Let's Encrypt verifies TXT record exists
4. Certificate issued and stored in `/opt/traefik/acme/acme.json`

## Prerequisites

- Route 53 hosted zone for `hartr.net` configured in AWS
- Nomad cluster with Traefik deployed (system job)
- Terraform installed with AWS provider configured
- AWS account access (Console or CLI)

## Step 1: Create IAM User and DNS Records

### 1.1 Configure Terraform Variables

Navigate to AWS Terraform directory:

```bash
cd terraform/aws
```

Create `terraform.tfvars`:

```bash
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
```

**Configure with your Traefik IP**:

```hcl
# terraform/aws/terraform.tfvars
aws_region = "us-east-1"

# Your homelab configuration:
# - Traefik runs as system job on 6 Nomad clients: 10.0.0.60-65
# - Home DNS points to 10.0.0.60 as primary Traefik endpoint
# - Route 53 DNS should match your home DNS configuration
traefik_server_ip = "10.0.0.60"
```

**About the setup**:
- **Traefik deployment**: System job on all 6 clients (10.0.0.60-65)
- **DNS routing**: Home DNS resolves `*.lab.hartr.net` → 10.0.0.60
- **Service discovery**: Consul automatically registers services
- **Traffic flow**: Route 53 (public) → 10.0.0.60 (home) → Traefik → Services

### 1.2 Apply Terraform Configuration

```bash
# Initialize
terraform init

# Review changes
terraform plan

# Create resources
terraform apply
```

**This creates**:
- IAM user `traefik-letsencrypt` with Route 53 permissions
- IAM policy for DNS record modifications
- Access key pair for Route 53 API access
- DNS records: `*.lab.hartr.net` and `lab.hartr.net` → your Traefik IP

### 1.3 Save AWS Credentials

**⚠️ CRITICAL**: Secret access key is only shown once. Save immediately:

```bash
# Display access key ID
terraform output traefik_aws_access_key_id

# Display secret access key (sensitive)
terraform output -raw traefik_aws_secret_access_key
```

Store these securely - needed for next step.

## Step 2: Configure Nomad Clients

### 2.1 Create Traefik ACME Directory

On all Nomad clients (10.0.0.60-65):

```bash
# Via Ansible (recommended)
cd ansible
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags nomad-client

# Or manually
ssh ubuntu@10.0.0.60 "sudo mkdir -p /opt/traefik/acme && sudo chmod 600 /opt/traefik/acme"
ssh ubuntu@10.0.0.61 "sudo mkdir -p /opt/traefik/acme && sudo chmod 600 /opt/traefik/acme"
ssh ubuntu@10.0.0.62 "sudo mkdir -p /opt/traefik/acme && sudo chmod 600 /opt/traefik/acme"
# Repeat for 10.0.0.63-65
```

**Why restricted permissions?**
- `acme.json` contains private keys
- Must be `600` or Traefik refuses to start

### 2.2 Update Nomad Client Configuration

Ansible role should add this to `/etc/nomad.d/nomad.hcl`:

```hcl
client {
  host_volume "traefik_acme" {
    path      = "/opt/traefik/acme"
    read_only = false
  }
}
```

### 2.3 Restart Nomad Clients

```bash
# Via Ansible
ansible nomad_clients -i inventory/hosts.yml -m systemd -a "name=nomad state=restarted" --become

# Or manually
ssh ubuntu@10.0.0.60 "sudo systemctl restart nomad"
# Repeat for other clients
```

### 2.4 Verify Host Volume

```bash
# Check volume is recognized
nomad node status -verbose | grep -A5 "Host Volumes"

# Or check specific node
nomad node status <node-id> | grep traefik_acme
```

Should see `traefik_acme` listed.

## Step 3: Store AWS Credentials in Nomad Variables

Set environment variables from Terraform outputs:

```bash
cd terraform/aws

export AWS_ACCESS_KEY_ID=$(terraform output -raw traefik_aws_access_key_id)
export AWS_SECRET_ACCESS_KEY=$(terraform output -raw traefik_aws_secret_access_key)
export AWS_HOSTED_ZONE_ID=$(terraform output -raw route53_zone_id)
```

Store in Nomad variables:

```bash
# Set Nomad address
export NOMAD_ADDR=http://10.0.0.50:4646

# Create variable (requires Nomad ACL token if enabled)
nomad var put nomad/jobs/traefik \
  aws_access_key="$AWS_ACCESS_KEY_ID" \
  aws_secret_key="$AWS_SECRET_ACCESS_KEY" \
  aws_hosted_zone_id="$AWS_HOSTED_ZONE_ID"

# Verify
nomad var get nomad/jobs/traefik
```

**Expected output**:
```
Namespace   = default
Path        = nomad/jobs/traefik
Create Time = 2026-02-05T...

Items
aws_access_key       = AKIA...
aws_secret_key       = <sensitive>
aws_hosted_zone_id   = Z...
```

**Why Nomad variables?**
- Encrypted at rest
- Access controlled by ACLs
- Available to jobs via templates
- Better than environment variables in job files

## Step 4: Deploy Traefik with SSL

### 4.1 Stop Existing Traefik

```bash
# Stop current job
nomad job stop traefik

# Wait for allocations to stop
nomad job status traefik
```

### 4.2 Deploy Updated Configuration

```bash
cd /Users/jackharter/Developer/hashi_homelab

# Review changes
nomad job plan jobs/system/traefik.nomad.hcl

# Deploy (runs on all 6 clients)
nomad job run jobs/system/traefik.nomad.hcl

# Verify deployment
nomad job status traefik
# Should show 6 allocations (one per client)
```

### 4.3 Monitor Certificate Request

Watch Traefik logs - pick any allocation:

```bash
# Get allocation ID
nomad job status traefik

# Follow logs
nomad alloc logs -f <alloc-id> traefik
```

**Successful output**:
```
level=info msg="Obtaining ACME certificate for domains [*.lab.hartr.net lab.hartr.net]"
level=info msg="Creating DNS challenge for domain *.lab.hartr.net"
level=info msg="Waiting for DNS propagation..."
level=info msg="The ACME server validated the DNS challenge"
level=info msg="Certificates obtained for domains [*.lab.hartr.net lab.hartr.net]"
```

**Common errors**:
- `error validating DNS challenge` → Check AWS credentials
- `rate limit exceeded` → Use Let's Encrypt staging server (see troubleshooting)
- `timeout` → DNS propagation delay; increase `delayBeforeCheck`

**Note**: All 6 Traefik instances share ACME storage via host volume, so certificate requests are coordinated.

## Step 5: Update Services for SSL

### 5.1 Service Configuration Pattern

Services need these Traefik tags for SSL:

```hcl
service {
  name = "myservice"
  port = "http"
  
  tags = [
    "traefik.enable=true",
    "traefik.http.routers.myservice.rule=Host(`myservice.lab.hartr.net`)",
    "traefik.http.routers.myservice.entrypoints=websecure",
    "traefik.http.routers.myservice.tls=true",
    "traefik.http.routers.myservice.tls.certresolver=letsencrypt",
  ]
}
```

**Key changes from HTTP-only**:
- `Host()` uses `*.lab.hartr.net` instead of `*.home`
- `entrypoints=websecure` (HTTPS/443) instead of `web` (HTTP/80)
- `tls=true` enables TLS
- `tls.certresolver=letsencrypt` specifies certificate resolver

### 5.2 Deploy Updated Services

```bash
# Stop and redeploy services
nomad job stop grafana
nomad job run jobs/services/grafana.nomad.hcl

nomad job stop prometheus
nomad job run jobs/services/prometheus.nomad.hcl

# Repeat for other services
```

**Or use Taskfile**:

```bash
task deploy:all  # Redeploys all services
```

## Step 6: Verification

### 6.1 Check DNS Resolution

```bash
# Verify DNS records
dig +short calibre.lab.hartr.net
dig +short prometheus.lab.hartr.net

# Should all return Traefik IP (10.0.0.60)
```

### 6.2 Test HTTPS Access

```bash
# Test with curl
curl -I https://calibre.lab.hartr.net
curl -I https://prometheus.lab.hartr.net
curl -I https://grafana.lab.hartr.net

# Should return HTTP/2 200 with valid SSL
```

### 6.3 Access Services in Browser

Open services:
- Traefik Dashboard: `http://10.0.0.60:8080` (insecure API, internal only)
- Grafana: `https://grafana.lab.hartr.net`
- Prometheus: `https://prometheus.lab.hartr.net`
- Calibre: `https://calibre.lab.hartr.net`

### 6.4 Verify Certificate Details

In browser:
1. Click lock icon in address bar
2. View certificate details
3. Verify:
   - Issued by: Let's Encrypt Authority X3
   - Common Name: `*.lab.hartr.net`
   - Subject Alternative Names: `*.lab.hartr.net`, `lab.hartr.net`
   - Expiration: ~90 days from issue

### 6.5 Check Traefik Dashboard

Access dashboard on any node:
- `http://10.0.0.60:8080` (primary)
- `http://10.0.0.61:8080` (secondary)
- `http://10.0.0.62:8080` (tertiary)

All dashboards show:
- **Routers**: Services with TLS enabled
- **Certificates**: `*.lab.hartr.net` with valid status
- **Services**: Consul-discovered services from all nodes

## Troubleshooting

### Issue: Certificate Not Issued

**Symptoms**: Errors in logs, certificate never appears.

**Solutions**:

1. **Check AWS credentials**:
   ```bash
   nomad var get nomad/jobs/traefik
   ```

2. **Verify Route 53 permissions**:
   ```bash
   cd terraform/aws
   terraform state show aws_iam_policy.traefik_route53
   ```
   Ensure policy allows `route53:ChangeResourceRecordSets`.

3. **Test with Let's Encrypt staging**:
   Edit `jobs/system/traefik.nomad.hcl`:
   ```yaml
   caServer: https://acme-staging-v02.api.letsencrypt.org/directory
   ```
   Avoids production rate limits during testing.

4. **Check DNS TXT record creation**:
   ```bash
   dig _acme-challenge.lab.hartr.net TXT
   ```
   During request, should see TXT records.

5. **Increase DNS propagation delay**:
   In `jobs/system/traefik.nomad.hcl`:
   ```yaml
   dnsChallenge:
     delayBeforeCheck: 60s  # Increase from default
   ```

### Issue: DNS Not Resolving

**Symptoms**: `dig` returns NXDOMAIN or no results.

**Solutions**:

1. **Verify Terraform applied**:
   ```bash
   cd terraform/aws
   terraform output dns_records_created
   ```

2. **Check Route 53 console**:
   - AWS Console → Route 53 → Hosted Zones → hartr.net
   - Verify A records: `*.lab.hartr.net` and `lab.hartr.net`

3. **Test with different DNS server**:
   ```bash
   dig @8.8.8.8 calibre.lab.hartr.net
   dig @1.1.1.1 calibre.lab.hartr.net
   ```

4. **Wait for propagation**: 5-10 minutes for global DNS propagation

### Issue: Services Not Accessible

**Symptoms**: DNS resolves, HTTPS connection fails/times out.

**Solutions**:

1. **Verify accessing from home network** (internal IP config requires this)

2. **Check Traefik routing**:
   ```bash
   # Traefik dashboard
   open http://10.0.0.60:8080
   
   # Or via API
   curl http://10.0.0.60:8080/api/http/routers
   ```

3. **Verify Consul service registration**:
   ```bash
   consul catalog services
   consul catalog service grafana
   ```

4. **Check Traefik logs across nodes**:
   ```bash
   nomad job status traefik  # Get all alloc IDs
   nomad alloc logs <alloc-id> traefik | grep -i error
   ```

### Issue: Rate Limits Hit

**Symptoms**: "too many certificates already issued" errors in logs.

**Context**: Let's Encrypt rate limits:
- 50 certificates per registered domain per week
- Wildcard certificates count as one certificate

**Solutions**:

1. **Use staging server during testing** (see above)

2. **Wait for rate limit reset** (1 week)

3. **Wildcard is efficient**: Current config requests single `*.lab.hartr.net` cert covering all services

4. **Check current rate limit status**: Visit https://crt.sh/?q=%.lab.hartr.net

### Issue: Certificate Renewal Fails

**Symptoms**: Certificates expire without automatic renewal.

**Solutions**:

1. **Check Traefik logs during renewal window** (~30 days before expiration):
   ```bash
   nomad alloc logs -f <traefik-alloc-id>
   ```

2. **Verify ACME storage persistence**:
   ```bash
   ssh ubuntu@10.0.0.60 "sudo ls -lh /opt/traefik/acme/"
   # Should show acme.json
   ```

3. **Ensure host volume mounted**:
   Traefik restarts preserve certificates via `traefik_acme` host volume.

4. **Manual renewal** (force):
   ```bash
   nomad job stop traefik
   ssh ubuntu@10.0.0.60 "sudo rm /opt/traefik/acme/acme.json"
   nomad job run jobs/system/traefik.nomad.hcl
   ```

### Issue: HTTP Redirects Not Working

**Symptoms**: `http://service.lab.hartr.net` doesn't redirect to HTTPS.

**Expected**: Traefik config includes automatic HTTP→HTTPS redirects:

```yaml
entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
          permanent: true
```

**Solutions**:

1. **Verify config loaded**:
   ```bash
   nomad alloc logs <traefik-alloc-id> | grep -i redirect
   ```

2. **Clear browser cache** and retry

3. **Test with curl**:
   ```bash
   curl -I http://calibre.lab.hartr.net
   # Should return HTTP 301/308 with Location: https://...
   ```

## Adding New Services

Use this pattern for any new service:

```hcl
job "myservice" {
  datacenters = ["dc1"]
  
  group "app" {
    network {
      port "http" {
        to = 8080  # Service's internal port
      }
    }

    service {
      name = "myservice"
      port = "http"
      
      tags = [
        "traefik.enable=true",
        "traefik.http.routers.myservice.rule=Host(`myservice.lab.hartr.net`)",
        "traefik.http.routers.myservice.entrypoints=websecure",
        "traefik.http.routers.myservice.tls=true",
        "traefik.http.routers.myservice.tls.certresolver=letsencrypt",
      ]
    }

    task "app" {
      driver = "docker"
      
      config {
        image = "your/image:latest"
        ports = ["http"]
      }
    }
  }
}
```

**No additional DNS or certificate configuration needed** - wildcard certificate covers all `*.lab.hartr.net` automatically!

## Security Considerations

### Credentials Management

- **Nomad Variables**: Encrypted at rest, access controlled by ACLs
- **Terraform State**: Contains sensitive data (secret access key) - secure it
- **IAM User**: Minimal permissions (Route 53 only)
- **Access Keys**: Rotate periodically using Terraform

### Network Security

- **Internal IP configuration**: Services only accessible from home network
- **SSL/TLS**: All traffic encrypted in transit
- **Traefik Dashboard**: Insecure API on port 8080 - internal access only
- **Firewall**: If exposing publicly, configure strict firewall rules

### Best Practices

1. **Use Terraform Cloud/remote state** for production
2. **Enable Nomad ACLs** to restrict variable access
3. **Rotate AWS credentials quarterly**:
   ```bash
   terraform taint aws_iam_access_key.traefik_letsencrypt
   terraform apply
   # Update Nomad variables with new credentials
   ```
4. **Monitor certificate expiration** (Traefik auto-renews at ~30 days)
5. **Backup ACME storage** or rely on automatic renewal:
   ```bash
   scp ubuntu@10.0.0.60:/opt/traefik/acme/acme.json ./backup/
   ```

### Terraform State Security

**Secure state file** (contains secret access key):

```bash
chmod 600 terraform/aws/terraform.tfstate
```

**Use remote state** (recommended for production):

```hcl
# terraform/aws/traefik-route53.tf
terraform {
  backend "s3" {
    bucket         = "your-terraform-state-bucket"
    key            = "traefik/route53/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}
```

**Recover from lost state**:

```bash
terraform import aws_iam_user.traefik_letsencrypt traefik-letsencrypt
terraform import aws_iam_policy.traefik_route53 arn:aws:iam::ACCOUNT:policy/traefik-route53
```

## Summary

**What we built**:
- ✅ Terraform configuration for AWS IAM and Route 53
- ✅ Automated SSL certificate provisioning via Let's Encrypt
- ✅ Wildcard certificate for `*.lab.hartr.net`
- ✅ Automatic HTTP → HTTPS redirects
- ✅ Secure credential storage in Nomad variables
- ✅ Services with SSL enabled

**Architecture**:

```
User → Home DNS (*.lab.hartr.net → 10.0.0.60)
         ↓
   Traefik (6 nodes: 10.0.0.60-65, SSL/TLS)
         ↓
   Consul Service Discovery
         ↓
   Nomad Services (distributed across clients)

Let's Encrypt ← Route 53 DNS-01 Challenge
```

**Maintenance**:
- Certificates auto-renew ~30 days before expiration
- New services automatically get SSL with correct Traefik tags
- No manual certificate management needed
- Monitor Traefik logs for renewal issues

---

**For additional help, see**:
- [CHEATSHEET.md](CHEATSHEET.md) - Quick reference commands
- [NEW_SERVICES_DEPLOYMENT.md](NEW_SERVICES_DEPLOYMENT.md) - Service deployment patterns
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Common issues and solutions
