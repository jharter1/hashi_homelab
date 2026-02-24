# New Services Deployment Guide

**Last Updated:** February 23, 2026

This guide covers the architecture, deployment strategy, container permission patterns, and specific instructions for running services on the Nomad cluster.

## Architecture: The "Holy Trinity"

The standard pattern for HashiCorp homelabs involves three components working together:

1. **Nomad**: Schedules and runs application containers (Docker).
2. **Consul**: Acts as the "Phonebook". When Nomad starts a container, it registers the service (IP and Port) with Consul.
3. **Traefik**: Acts as the "Switchboard". It connects to Consul, watches for services with specific tags (e.g., `traefik.enable=true`), and automatically creates routing rules to expose them on port 80/443.

### Traffic Flow

```
User → Traefik (Port 80/443) → Consul Lookup → Nomad Client IP:Port → Container
```

**How it works**:
1. User accesses `https://service.lab.hartr.net`
2. Traefik receives request and queries Consul
3. Consul returns healthy service instances registered by Nomad
4. Traefik proxies request to service with SSL termination

### Required Service Tags

To expose a service via Traefik, add tags in the Nomad job file:

```hcl
service {
  name = "myapp"
  port = "http"
  
  tags = [
    "traefik.enable=true",
    "traefik.http.routers.myapp.rule=Host(`myapp.lab.hartr.net`)",
    "traefik.http.routers.myapp.entrypoints=websecure",
    "traefik.http.routers.myapp.tls=true",
    "traefik.http.routers.myapp.tls.certresolver=letsencrypt",
  ]
}
```

See [SERVICES.md](SERVICES.md) for detailed Traefik SSL configuration.

## Service Categories & Ideas

### 🛠️ Core Infrastructure
- **Traefik**: Ingress controller (system job)
- **Homepage / Dashy**: Dashboard for all services
- **Docker Registry**: Image caching and private registry

### 📊 Observability (LGTM Stack)
- **Prometheus**: Metrics collection and storage
- **Grafana**: Visualization dashboards
- **Loki**: Log aggregation
- **Tempo**: Distributed tracing (future)

### 📚 Knowledge Management
- **Trilium Notes**: Hierarchical note-taking
- **Linkwarden**: Bookmark archiving with tagging
- **Wallabag**: Read-it-later for articles
- **BookStack**: Organized documentation platform

### 🏠 Home Automation
- **Home Assistant**: Smart home control (future)
- **Mosquitto**: MQTT broker for IoT (future)
- **Zigbee2MQTT**: Zigbee device integration (future)

### 🎬 Media & Content
- **Jellyfin / Plex**: Media streaming (future)
- **Sonarr / Radarr**: Media management (future)
- **Calibre**: E-book library
- **Immich**: Photo/video backup with ML features

### 🧪 Development & CI/CD
- **Gitea**: Self-hosted Git repositories
- **Woodpecker CI**: CI/CD pipelines
- **Harbor**: Enterprise container registry with scanning
- **Code-Server**: VS Code in browser (future)

### 🗂️ Document Management
- **Paperless-ngx**: Document OCR and organization
- **Draw.io**: Diagramming and flowcharts

### 🌐 Network & Monitoring
- **Speedtest Tracker**: Network speed monitoring
- **Uptime-Kuma**: Service availability monitoring
- **Tailscale**: VPN remote access

## Container Permission Patterns & Gotchas

When deploying new services, understanding container permission patterns is critical for avoiding deployment failures. This section documents common patterns learned from troubleshooting 150+ failed allocations.

### Understanding Docker Driver Limitations

**Nomad's Docker driver has restricted capabilities:**

```hcl
# ❌ This won't work - Nomad rejects capability additions
config {
  cap_add = ["SETUID", "SETGID", "CHOWN"]
}
# Error: driver does not allow the following capabilities: setgid, setuid, chown
```

**Why this matters:**
- Many containers need to change user/group IDs during initialization
- Init systems (s6-overlay, tini) often require root → drop privileges
- NFS volumes may have specific ownership requirements (1000:1000)
- Containers using su-exec, gosu, or setgroups will fail without proper configuration

### Common Error Patterns

#### 1. su-exec/setgroups Failures

**Symptoms:**
```
su-exec: setgroups: Operation not permitted
chown: Operation not permitted
s6-svscan: fatal: unable to open .s6-svscan/lock: Permission denied
Exit Code: 111 or 256
```

**Root Cause:** Container needs SETUID/SETGID capabilities for privilege dropping.

**Solution Pattern 1 - Use Privileged Mode:**
```hcl
config {
  image = "linuxserver/bookstack:latest"
  network_mode = "host"
  ports = ["http"]
  privileged = true  # ✅ Grants necessary capabilities
}
user = "1000:1000"  # Match NFS ownership
```

**Solution Pattern 2 - Use Rootless Image:**
```hcl
config {
  image = "gitea/gitea:latest-rootless"  # ✅ Designed for restricted envs
  network_mode = "host"
  ports = ["http"]
}
user = "1000:1000"  # Runs as this user from start
```

#### 2. NFS Permission Denied Errors

**Symptoms:**
```
Error: EACCES: permission denied, open '/data/config.json'
mkdir: cannot create directory '/data/uploads': Permission denied
```

**Root Cause:** NFS ownership doesn't match container user.

**Solution:** Pre-create volumes with correct ownership in Ansible:
```yaml
- name: Create host volume directories
  ansible.builtin.file:
    path: "/mnt/nas/{{ item.name }}"
    state: directory
    owner: "{{ item.owner | default('root') }}"
    group: "{{ item.group | default('root') }}"
  loop:
    - { name: 'gitea_data', owner: '1000', group: '1000' }
    - { name: 'postgres_data', owner: '70', group: '70' }    # PostgreSQL user
    - { name: 'prometheus_data', owner: '65534', group: '65534' }  # nobody user
```

#### 3. Init System Conflicts

**Symptoms:**
```
s6-applyuidgid: fatal: unable to set supplementary group list
Container fails when using: user = "1000:1000"
Works without user directive but has wrong NFS permissions
```

**Root Cause:** s6-overlay and similar init systems MUST start as root, then drop privileges.

**Decision Matrix:**

| Container Type | Use `privileged=true` | Use`user` Directive | Use Rootless Image |
|----------------|------------------------|---------------------|---------------------|
| LinuxServer.io | ✅ Yes | ✅ Yes (both!) | ❌ N/A |
| Official Alpine | ✅ Yes | ❌ No | Check for -rootless tag |
| Standard images with s6 | ✅ Yes | ❌ No | Check for -rootless tag |
| Rootless variants | ❌ No | ✅ Yes | ✅ Use these |
| Simple stateless apps | ❌ Optional | ✅ Yes | ❌ N/A |

### Service-Specific Patterns

#### LinuxServer.io Containers (Bookstack, Calibre, Speedtest)

**Pattern:**
```hcl
config {
  image = "lscr.io/linuxserver/bookstack:latest"
  network_mode = "host"
  ports = ["http"]
  privileged = true  # ✅ Required for s6-overlay
}
user = "1000:1000"  # ✅ Also needed - LinuxServer.io supports both

env {
  PUID = "1000"  # May also be needed depending on image
  PGID = "1000"
}
```

**Why both?**
- `privileged = true` - Allows s6-overlay init system to function
- `user = "1000:1000"` - Ensures file operations match NFS ownership

#### Gitea (Special Case)

**❌ Standard image fails:**
```hcl
config {
  image = "gitea/gitea:latest"  # Has s6-overlay
}
user = "1000:1000"  # Breaks s6 initialization
# Result: s6-svscan: fatal: unable to open .s6-svscan/lock
```

**✅ Use rootless instead:**
```hcl
config {
  image = "gitea/gitea:latest-rootless"  # No s6-overlay
}
user = "1000:1000"  # Works perfectly
```

**Gitea Lessons Learned:**
- Standard image: 153 failed allocations over 3 deployment attempts
- Rootless image: Successful on first try
- Always check for `-rootless` tags when containers have init systems

#### PostgreSQL

**Pattern:**
```hcl
config {
  image = "postgres:16-alpine"
  ports = ["db"]
  privileged = true  # ✅ Required for su-exec
}
# No user directive - runs as UID 70 internally
```

**NFS ownership:**
```yaml
- { name: 'postgres_data', owner: '70', group: '70' }
```

#### Prometheus & Node Exporters

**Pattern:**
```hcl
config {
  image = "prom/prometheus:latest"
  ports = ["http"]
  privileged = true  # ✅ Needed for process monitoring
}
# Runs as UID 65534 (nobody) internally
```

**NFS ownership:**
```yaml
- { name: 'prometheus_data', owner: '65534', group: '65534' }
```

### Quick Reference: When to Use What

**Start with this checklist for every new service:**

1. **Is it a LinuxServer.io image?**
   - ✅ Yes → Add `privileged = true` AND `user = "1000:1000"`
   - ✅ Yes → **Mount a custom nginx config** if your static port is not 80. See TROUBLESHOOTING.md "LinuxServer.io Images — Custom Port Configuration". All lscr.io images default nginx to port 80 regardless of the Nomad static port.

2. **Does it use s6-overlay, tini, or similar init?**
   - ✅ Yes → Check for rootless image first, otherwise use `privileged = true`
   - ❌ No → Safe to use `user = "1000:1000"` without privileged

3. **What UID does the container run as?**
   - Check image docs or `docker inspect`
   - Set NFS ownership to match in Ansible

4. **Does it bind privileged ports (<1024)?**
   - ✅ Yes → Need `privileged = true` (e.g., Traefik on 80/443)

5. **Is there a -rootless or -unprivileged tag?**
   - ✅ Yes → Strongly prefer these for easier permission management

6. **Does it have a sidecar database?**
   - ✅ Yes → Pick an unused port from the port inventory above and document it there. Port conflicts cause silent placement failures with host networking.

### Debugging Permission Issues

**Step-by-step troubleshooting:**

```bash
# 1. Check allocation logs for permission errors
nomad alloc logs -stderr <alloc-id> | grep -i "permission\|denied\|setgroups\|chown"

# 2. Verify NFS ownership
ssh ubuntu@10.0.0.60 "ls -ld /mnt/nas/<volume>_data"

# 3. Check what user container expects
nomad alloc exec -task <taskname> <alloc-id> id
# Compare to NFS ownership

# 4. Look for s6-overlay or init system
nomad alloc logs <alloc-id> | grep -i "s6-\|tini\|su-exec"

# 5. Try privileged mode first
# Add: privileged = true to config block
# Redeploy and check logs again
```

### Prevention Checklist

**Before deploying a new service:**

- [ ] Check image documentation for required uid/gid
- [ ] Search for rootless/unprivileged image variants
- [ ] Add volume directories to Ansible with correct ownership
- [ ] Add host_volume blocks to Nomad client template
- [ ] Start with `privileged = true` for s6-overlay containers
- [ ] Use `user = "1000:1000"` for most app data
- [ ] Test deployment and check logs for permission errors
- [ ] Remove `privileged = true` only if it works without it

**For more details, see:**
- Full troubleshooting guide: `docs/TROUBLESHOOTING.md`
- Gitea-specific lessons: Section "Gitea" in TROUBLESHOOTING.md
- NFS configuration: `docs/INFRASTRUCTURE.md`

## Recent Services Deployed

This section covers 8 new services added to the homelab focused on education, knowledge management, and development tools.

## Services Added

1. **Trilium Notes** - Personal knowledge management with hierarchical notes
2. **Linkwarden** - Bookmark manager with archiving and tagging (with dedicated PostgreSQL)
3. **Wallabag** - Read-it-later service for articles (with dedicated PostgreSQL)
4. **Woodpecker CI** - CI/CD pipeline integrated with Gitea
5. **Harbor** - Enterprise-grade container registry with vulnerability scanning (with dedicated PostgreSQL)
6. **Paperless-ngx** - Document management with OCR (with dedicated PostgreSQL and Redis)
7. **Draw.io** - Diagramming and flowchart tool
8. **BookStack** - Organized documentation platform (uses shared MariaDB)

**Note:** FreshRSS was already deployed, so it was not recreated.

**Architecture Note:** Each PostgreSQL-dependent service now has its own dedicated PostgreSQL instance for better isolation, resource management, and fault tolerance. This follows microservices best practices.

## Job Files Created

All job files are located in `jobs/services/` with the following structure:

- `jobs/services/media/trilium/trilium.nomad.hcl`
- `jobs/services/media/linkwarden/linkwarden.nomad.hcl`
- `jobs/services/media/wallabag/wallabag.nomad.hcl`
- `jobs/services/media/paperless/paperless.nomad.hcl`
- `jobs/services/media/bookstack/bookstack.nomad.hcl`
- `jobs/services/media/drawio/drawio.nomad.hcl`
- `jobs/services/development/woodpecker/woodpecker.nomad.hcl`
- `jobs/services/infrastructure/registry/registry.nomad.hcl` (Harbor)

## Prerequisites

### 1. Create Host Volumes on Nomad Clients

**CRITICAL:** When adding new services with host volumes, you MUST perform TWO steps:

#### Step 1: Add volumes to Ansible base-system role

Add volume definitions to `ansible/roles/base-system/tasks/main.yml` in the "Create host volume directories" task:

```yaml
- name: Create host volume directories
  ansible.builtin.file:
    path: "{{ nas_mount_point }}/{{ item.name }}"
    state: directory
    owner: "{{ item.owner | default('root') }}"
    group: "{{ item.group | default('root') }}"
    mode: "{{ item.mode | default('0755') }}"
  loop:
    # ... existing volumes ...
    
    # Knowledge Management (NEW)
    - { name: 'trilium_data', owner: '1000', group: '1000', mode: '0755' }
    - { name: 'linkwarden_data', owner: '1000', group: '1000', mode: '0755' }
    - { name: 'linkwarden_postgres_data', mode: '0755' }
    - { name: 'wallabag_data', owner: '1000', group: '1000', mode: '0755' }
    - { name: 'wallabag_images', owner: '1000', group: '1000', mode: '0755' }
    - { name: 'wallabag_postgres_data', mode: '0755' }
    - { name: 'paperless_data', owner: '1000', group: '1000', mode: '0755' }
    - { name: 'paperless_media', owner: '1000', group: '1000', mode: '0755' }
    - { name: 'paperless_consume', owner: '1000', group: '1000', mode: '0755' }
    - { name: 'paperless_export', owner: '1000', group: '1000', mode: '0755' }
    - { name: 'paperless_postgres_data', mode: '0755' }
    - { name: 'paperless_redis', owner: '999', group: '999', mode: '0755' }
    - { name: 'bookstack_config', owner: '1000', group: '1000', mode: '0755' }
    - { name: 'woodpecker_data', owner: '1000', group: '1000', mode: '0755' }
    - { name: 'harbor_data', owner: '10000', group: '10000', mode: '0755' }
    - { name: 'harbor_registry', owner: '10000', group: '10000', mode: '0755' }
    - { name: 'harbor_redis', owner: '999', group: '999', mode: '0755' }
    - { name: 'harbor_postgres_data', mode: '0755' }
    - { name: 'drawio_data', owner: '1000', group: '1000', mode: '0755' }
```

#### Step 2: Add host_volume blocks to Nomad client template

**THIS IS THE CRITICAL STEP THAT IS OFTEN FORGOTTEN!**

Add `host_volume` blocks to `ansible/roles/nomad-client/templates/nomad-client.hcl.j2`:

```hcl
client {
  enabled = true
  
  # ... existing volumes ...
  
  # Knowledge Management
  host_volume "trilium_data" {
    path      = "{{ nas_mount_point }}/trilium_data"
    read_only = false
  }
  
  host_volume "linkwarden_data" {
    path      = "/mnt/nas/linkwarden_data"
    read_only = false
  }
  
  host_volume "wallabag_data" {
    path      = "/mnt/nas/wallabag_data"
    read_only = false
  }
  
  host_volume "wallabag_images" {
    path      = "/mnt/nas/wallabag_images"
    read_only = false
  }
  
  host_volume "paperless_data" {
    path      = "/mnt/nas/paperless_data"
    read_only = false
  }
  
  host_volume "paperless_media" {
    path      = "/mnt/nas/paperless_media"
    read_only = false
  }
  
  host_volume "paperless_consume" {
    path      = "/mnt/nas/paperless_consume"
    read_only = false
  }
  
  host_volume "paperless_export" {
    path      = "/mnt/nas/paperless_export"
    read_only = false
  }
  
  host_volume "bookstack_config" {
    path      = "/mnt/nas/bookstack_config"
    read_only = false
  }
  
  host_volume "woodpecker_data" {
    path      = "/mnt/nas/woodpecker_data"
    read_only = false
  }
  
  host_volume "harbor_data" {
    path      = "/mnt/nas/harbor_data"
    read_only = false
  }
  
  host_volume "harbor_registry" {
    path      = "/mnt/nas/harbor_registry"
    read_only = false
  }
  
  host_volume "harbor_redis" {
    path      = "/mnt/nas/harbor_redis"
    read_only = false
  }
  
  host_volume "harbor_postgres_data" {
    path      = "/mnt/nas/harbor_postgres_data"
    read_only = false
  }
  
  host_volume "linkwarden_postgres_data" {
    path      = "/mnt/nas/linkwarden_postgres_data"
    read_only = false
  }
  
  host_volume "wallabag_postgres_data" {
    path      = "/mnt/nas/wallabag_postgres_data"
    read_only = false
  }
  
  host_volume "paperless_postgres_data" {
    path      = "/mnt/nas/paperless_postgres_data"
    read_only = false
  }
}
```

**WITHOUT THIS STEP, YOUR JOBS WILL FAIL WITH "missing compatible host volumes" ERRORS!**

The directories created in Step 1 are just filesystem storage. Nomad clients need to be explicitly configured to expose these as mountable volumes to jobs.

#### Step 3: Apply configuration and restart Nomad clients

Run Ansible to create directories and update Nomad client configs:

```bash
task ansible:configure
```

**CRITICAL**: After Ansible completes, you MUST manually restart all Nomad clients for them to register the new volumes:

```bash
for ip in 10.0.0.60 10.0.0.61 10.0.0.62 10.0.0.63 10.0.0.64 10.0.0.65; do
  ssh ubuntu@$ip "sudo systemctl restart nomad"
done
```

Wait 30-60 seconds for clients to reconnect, then verify volumes are registered:

```bash
nomad node status dev-nomad-client-1 | grep -A 50 "Host Volumes"
```

You should see all your new volumes listed. If not, check `/etc/nomad.d/nomad.hcl` on the client to verify the configuration was applied.

### 2. Create Vault Secrets

Run the following commands to create the required secrets in Vault:

```bash
# Set Vault address
export VAULT_ADDR="http://10.0.0.30:8200"
vault login  # Use your Vault token

# PostgreSQL database passwords
vault kv put secret/postgres/linkwarden password="$(openssl rand -base64 32)"
vault kv put secret/postgres/wallabag password="$(openssl rand -base64 32)"
vault kv put secret/postgres/paperless password="$(openssl rand -base64 32)"
vault kv put secret/postgres/harbor password="$(openssl rand -base64 32)"

# Application secrets
vault kv put secret/linkwarden/nextauth secret="$(openssl rand -base64 32)"
vault kv put secret/wallabag/secret value="$(openssl rand -hex 32)"
vault kv put secret/paperless/secret value="$(openssl rand -hex 32)"
**Note:** Unlike the previous centralized PostgreSQL approach, each service now has its own dedicated PostgreSQL instance. This is NOT required - the new services will deploy their own PostgreSQL containers.

If you want to keep the centralized PostgreSQL for existing services (Gitea, Authelia, Grafana, etc.), you can leave it as-is. The new services are completely independent.

## Deployment

Deploy each service using Nomad. Each service that requires PostgreSQL includes its own dedicated PostgreSQL instance as a sidecar task within the same job group:

```bash
# Set Nomad address
export NOMAD_ADDR="http://10.0.0.50:4646"

# Deploy services (PostgreSQL sidecars are included in each job)
nomad job run jobs/services/media/trilium/trilium.nomad.hcl
nomad job run jobs/services/media/linkwarden/linkwarden.nomad.hcl  # Includes PostgreSQL
nomad job run jobs/services/media/wallabag/wallabag.nomad.hcl      # Includes PostgreSQL
nomad job run jobs/services/media/paperless/paperless.nomad.hcl    # Includes PostgreSQL + Redis
nomad job run jobs/services/media/bookstack/bookstack.nomad.hcl
nomad job run jobs/services/media/drawio/drawio.nomad.hcl
nomad job run jobs/services/development/woodpecker/woodpecker.nomad.hcl
nomad job run jobs/services/infrastructure/registry/registry.nomad.hcl  # Harbor - includes PostgreSQL + Redis

# Redeploy MariaDB to add BookStack database
nomad job run jobs/services/databases/mariadb/mariadb.nomad.hcl

# Redeploy homepage to show new services
nomad job run jobs/services/homepage.nomad.hcl
```

## Service Access

All services are accessible via their respective URLs:

- **Trilium Notes**: https://trilium.lab.hartr.net
- **Linkwarden**: https://linkwarden.lab.hartr.net
- **Wallabag**: https://wallabag.lab.hartr.net
- **FreshRSS**: https://freshrss.lab.hartr.net (already deployed)
- **Paperless-ngx**: https://paperless.lab.hartr.net
- **BookStack**: https://bookstack.lab.hartr.net
- **Woodpecker CI**: https://ci.lab.hartr.net
- **Harbor**: https://harbor.lab.hartr.net
- **Draw.io**: https://diagrams.lab.hartr.net

## Port Allocations

**Application HTTP ports:**
- 8081 - Wallabag
- 8082 - FreshRSS
- 8083 - BookStack
- 8084 - Woodpecker CI (HTTP)
- 8085 - Draw.io
- 8086 - Paperless-ngx
- 8765 - Speedtest Tracker
- 9000 - Woodpecker CI (gRPC)
- 5000 - Harbor (HTTP)

**Sidecar database ports (must be unique across all jobs on a node — host networking):**
- 3307 - BookStack (MariaDB)
- 5433 - Linkwarden (PostgreSQL)
- 5434 - Wallabag (PostgreSQL)
- 5435 - FreshRSS (PostgreSQL) — NOTE: paperless also used 5435; potential conflict if co-scheduled
- 5436 - Grafana (PostgreSQL)
- 5437 - Gitea (PostgreSQL)
- 5438 - Vaultwarden (PostgreSQL)
- 5439 - Speedtest Tracker (PostgreSQL)
- 6380 - Paperless (Redis)
- 6381 - Harbor (Redis)
- Harbor PostgreSQL: 5436 (conflicts with Grafana — update before deploying Harbor)

**When adding a new service with a sidecar database, pick an unused port and add it to this list.**

## Initial Setup

### Linkwarden
1. Access https://linkwarden.lab.hartr.net
2. Create an account (first user is admin)
3. Configure settings and start adding bookmarks

### Wallabag
1. Access https://wallabag.lab.hartr.net
2. Default credentials may be in the container logs
3. Change password immediately after first login
4. Configure reading settings

### Paperless-ngx
1. Access https://paperless.lab.hartr.net
2. Login with admin credentials from Vault (`secret/paperless/admin`)
3. Configure OCR languages and consumption settings
4. Upload documents to `/mnt/nas/paperless_consume` or via web interface

### BookStack
1. Access https://bookstack.lab.hartr.net
2. Default credentials: `admin@admin.com` / `password`
3. Change password immediately
4. Create shelves, books, and pages

### Woodpecker CI
1. Configure OAuth in Gitea first:
   - Go to Gitea -> Settings -> Applications
   - Create OAuth2 Application
   - Name: "Woodpecker CI"
   - Redirect URI: https://ci.lab.hartr.net/authorize
   - Copy Client ID and Secret to Vault
2. Redeploy Woodpecker with correct credentials
3. Access https://ci.lab.hartr.net
4. Login with Gitea account
5. Enable repositories and add `.woodpecker.yml` files

### Trilium Notes
1. Access https://trilium.lab.hartr.net
2. Set up initial password
3. Start creating your knowledge base

### Draw.io
1. Access https://diagrams.lab.hartr.net
2. No setup required - start creating diagrams
3. Save files locally or to connected storage

### Harbor
1. Access https://harbor.lab.hartr.net
2. Login with default credentials:
   - Username: `admin`
   - Password: From Vault (`secret/harbor/admin`)
3. Configure project and user settings
4. Push images to Harbor:
   ```bash
   # Login to registry
   docker login harbor.lab.hartr.net
   
   # Tag and push images
   docker tag myimage:latest harbor.lab.hartr.net/library/myimage:latest
   docker push harbor.lab.hartr.net/library/myimage:latest
   ```
5. Enable vulnerability scanning in project settings (optional)

## Monitoring

All services are registered with Consul and monitored by:
- Nomad UI: http://10.0.0.50:4646
- Consul UI: http://10.0.0.50:8500
- Traefik Dashboard: https://traefik.lab.hartr.net
- Homepage Dashboard: https://homepage.lab.hartr.net (shows all services)

## Resource Usage

EsLinkwarden PostgreSQL: 500 CPU, 256 MB RAM
- Wallabag: 500 CPU, 512 MB RAM
- Wallabag PostgreSQL: 500 CPU, 256 MB RAM
- Paperless-ngx: 1000 CPU, 1024 MB RAM
- Paperless PostgreSQL: 500 CPU, 256 MB RAM
- Paperless Redis: 200 CPU, 128 MB RAM
- BookStack: 500 CPU, 512 MB RAM
- Woodpecker Server: 500 CPU, 512 MB RAM
- Woodpecker Agent: 1000 CPU, 1024 MB RAM
- Harbor: 1000 CPU, 1024 MB RAM
- Harbor PostgreSQL: 500 CPU, 512 MB RAM
- Harbor Redis: 200 CPU, 128 MB RAM
- Draw.io: 500 CPU, 256 MB RAM

**Total Additional Resources:**
- CPU: 8400 units
- Memory: 7424 MB (~7.3 MB RAM

**Total Additional Resources:**
- CPU: 6200 units
- Memory: 6016 MB (~5.9 GB)

Ensure your Nomad clients have sufficient resources for these services.

## Troubleshooting

### "missing compatible host volumes" error

**Symptom:** Job fails to place with error like:
```
Constraint "missing compatible host volumes": 6 nodes excluded by filter
```

**Cause:** Nomad clients don't have the required `host_volume` blocks in their configuration, even if the directories exist on NFS.

**Solution:**
1. Verify directory exists: `ssh ubuntu@10.0.0.60 "ls -la /mnt/nas/ | grep <volume_name>"`
2. Check if volume is configured in template: `grep "<volume_name>" ansible/roles/nomad-client/templates/nomad-client.hcl.j2`
3. If missing from template, add the `host_volume` block (see Prerequisites above)
4. Run `task ansible:configure` to update all client configs
5. **CRITICAL**: Manually restart all Nomad clients:
   ```bash
   for ip in 10.0.0.60 10.0.0.61 10.0.0.62 10.0.0.63 10.0.0.64 10.0.0.65; do
     ssh ubuntu@$ip "sudo systemctl restart nomad"
   done
   ```
6. Verify volumes are registered: `nomad node status dev-nomad-client-1 | grep -A 50 "Host Volumes"`
7. Retry job deployment

**Remember:** Creating a directory on NFS is NOT enough. You must also add the corresponding `host_volume` block to the Nomad client template!

### Service won't start
- Check Nomad allocation logs: `nomad alloc logs <alloc-id>`
- Verify Vault secrets exist: `vault kv get secret/<path>`
- Ensure volumes are mounted: `ssh ubuntu@10.0.0.60 "ls -la /mnt/nas/"`

### Database connection errors
- Verify database service is running: `nomad status postgresql` or `nomad status mariadb`
- Check database was created: Connect to PostgreSQL/MariaDB and list databases
- Verify Vault credentials match database user passwords

### Volume permission errors
- Ensure volumes have correct ownership: `chown -R 1000:1000 /mnt/nas/<volume>`
- Check Nomad client configuration includes the volume definition
- Restart Nomad client after adding volumes

### Traefik routing issues
- Verify service is registered in Consul: http://10.0.0.50:8500
- Check Traefik tags in job file match expected pattern
- Review Traefik logs: `nomad alloc logs -job traefik`

### PostgreSQL authentication failures

**Symptom:** Service logs show `password authentication failed for user <service_name>`

**Root Cause:** Database or user doesn't exist, even though PostgreSQL is running.

**Solution:**
1. **Don't create users manually** - Use the automated init-databases system (see `docs/POSTGRESQL.md`)
2. Verify the service is listed in the init-databases task in `jobs/services/databases/postgresql/postgresql.nomad.hcl`
3. If missing, add database initialization SQL to the init script
4. Redeploy PostgreSQL: `nomad job run jobs/services/databases/postgresql/postgresql.nomad.hcl`
5. Check init-databases task logs: `nomad alloc logs <alloc-id> init-databases`
6. Verify database exists:
   ```fish
   ssh ubuntu@10.0.0.60 "sudo docker exec -i \$(sudo docker ps | grep postgres | grep -v backup | awk '{print \$1}') \\
     psql -U postgres -c '\\l' | grep <service_name>"
   ```

**Prevention:** Always use the automated PostgreSQL initialization system. Manual database creation is error-prone and not idempotent.

### Homepage dashboard widgets not working

**Symptom:** Homepage widgets show "No data" or fail to load, even though services are running.

**Root Cause:** Homepage widget configuration has hardcoded IP addresses, but Nomad schedules services on different nodes.

**Solution:**
1. Find the actual service allocation IP:
   ```fish
   nomad job status <service-name> | grep -A 2 'Allocations'
   nomad alloc status <alloc-id> | grep -A 3 'Allocation Addresses'
   ```
2. Update widget URL in `configs/homepage/services.yaml` with correct IP:port
3. Sync and redeploy homepage:
   ```fish
   task homepage:update
   ```

**Prevention:** Consider using Consul service discovery or Nomad API for dynamic widget URLs instead of hardcoding IPs.

### Speedtest Tracker admin user creation

**Symptom:** Can't log into Speedtest Tracker after deployment.

**Common Gotchas:**
1. **Interactive commands don't work over SSH:**
   ```fish
   # ❌ This fails:
   ssh ubuntu@10.0.0.63 "sudo docker exec -it <container> php /app/www/artisan make:filament-user"
   # Error: NonInteractiveValidationException
   ```

2. **Use non-interactive flags instead:**
   ```fish
   # ✅ This works:
   ssh ubuntu@10.0.0.63 "sudo docker exec <container> php /app/www/artisan make:filament-user \\
     --name='Admin' --email='admin@admin.com' --password='password'"
   ```

3. **Default role is 'user', not 'admin':**
   - The `make:filament-user` command creates users with role='user' by default
   - Must manually upgrade to admin role in database:
   ```fish
   ssh ubuntu@10.0.0.60 "sudo docker exec \$(sudo docker ps | grep postgres | grep -v backup | awk '{print \$1}') \\
     psql -U speedtest -d speedtest -c \"UPDATE users SET role = 'admin' WHERE email = 'admin@admin.com';\""
   ```

4. **Container IDs change between queries:**
   - Always run `docker ps` immediately before exec commands
   - Container ID from 5 minutes ago may no longer be valid

**Full Workflow:**
```fish
# 1. Get current container ID
CONTAINER_ID=$(ssh ubuntu@10.0.0.63 "sudo docker ps | grep speedtest | awk '{print \$1}'")

# 2. Create user with non-interactive flags
ssh ubuntu@10.0.0.63 "sudo docker exec $CONTAINER_ID php /app/www/artisan make:filament-user \\
  --name='Admin' --email='admin@admin.com' --password='password'"

# 3. Upgrade to admin role
PG_CONTAINER=$(ssh ubuntu@10.0.0.60 "sudo docker ps | grep postgres | grep -v backup | awk '{print \$1}'")
ssh ubuntu@10.0.0.60 "sudo docker exec $PG_CONTAINER psql -U speedtest -d speedtest \\
  -c \"UPDATE users SET role = 'admin' WHERE email = 'admin@admin.com';\""

# 4. Verify
ssh ubuntu@10.0.0.60 "sudo docker exec $PG_CONTAINER psql -U speedtest -d speedtest \\
  -c 'SELECT id, name, email, role FROM users;'"
```
