# Example: Protecting Services with Authelia

This document shows before/after examples for adding Authelia SSO protection to your Nomad services.

## Pattern: Add Authelia Middleware

To protect any service, add **one line** to the Traefik tags:

```hcl
"traefik.http.routers.SERVICE_NAME.middlewares=authelia@consulcatalog"
```

## Example 1: Grafana

### Before (Unprotected)

```hcl
service {
  name = "grafana"
  port = "http"
  tags = [
    "traefik.enable=true",
    "traefik.http.routers.grafana.rule=Host(`grafana.lab.hartr.net`)",
    "traefik.http.routers.grafana.entrypoints=websecure",
    "traefik.http.routers.grafana.tls=true",
    "traefik.http.routers.grafana.tls.certresolver=letsencrypt",
  ]
  check {
    type     = "http"
    path     = "/api/health"
    interval = "10s"
    timeout  = "2s"
  }
}
```

### After (Protected)

```hcl
service {
  name = "grafana"
  port = "http"
  tags = [
    "traefik.enable=true",
    "traefik.http.routers.grafana.rule=Host(`grafana.lab.hartr.net`)",
    "traefik.http.routers.grafana.entrypoints=websecure",
    "traefik.http.routers.grafana.tls=true",
    "traefik.http.routers.grafana.tls.certresolver=letsencrypt",
    # ⬇️ ADD THIS LINE ⬇️
    "traefik.http.routers.grafana.middlewares=authelia@consulcatalog",
  ]
  check {
    type     = "http"
    path     = "/api/health"
    interval = "10s"
    timeout  = "2s"
  }
}
```

## Example 2: Prometheus

### Before

```hcl
tags = [
  "monitoring",
  "prometheus",
  "traefik.enable=true",
  "traefik.http.routers.prometheus.rule=Host(`prometheus.lab.hartr.net`)",
  "traefik.http.routers.prometheus.entrypoints=websecure",
  "traefik.http.routers.prometheus.tls=true",
  "traefik.http.routers.prometheus.tls.certresolver=letsencrypt",
]
```

### After

```hcl
tags = [
  "monitoring",
  "prometheus",
  "traefik.enable=true",
  "traefik.http.routers.prometheus.rule=Host(`prometheus.lab.hartr.net`)",
  "traefik.http.routers.prometheus.entrypoints=websecure",
  "traefik.http.routers.prometheus.tls=true",
  "traefik.http.routers.prometheus.tls.certresolver=letsencrypt",
  "traefik.http.routers.prometheus.middlewares=authelia@consulcatalog",
]
```

## Example 3: Jenkins (Multiple Services in One Job)

When a job has multiple services, protect each router separately:

```hcl
service {
  name = "jenkins"
  port = "http"
  tags = [
    "ci-cd",
    "traefik.enable=true",
    "traefik.http.routers.jenkins.rule=Host(`jenkins.lab.hartr.net`)",
    "traefik.http.routers.jenkins.entrypoints=websecure",
    "traefik.http.routers.jenkins.tls=true",
    "traefik.http.routers.jenkins.tls.certresolver=letsencrypt",
    "traefik.http.routers.jenkins.middlewares=authelia@consulcatalog",
  ]
  check {
    type     = "tcp"
    interval = "10s"
    timeout  = "2s"
  }
}
```

## Example 4: MinIO (Multi-Service with Different Protection Levels)

MinIO has both a console (web UI) and S3 API. You might want to protect only the console:

```hcl
# Console service (Web UI) - PROTECTED
service {
  name = "minio-console"
  port = "console"
  tags = [
    "storage",
    "s3",
    "traefik.enable=true",
    "traefik.http.routers.minio-console.rule=Host(`minio.lab.hartr.net`)",
    "traefik.http.routers.minio-console.entrypoints=websecure",
    "traefik.http.routers.minio-console.tls=true",
    "traefik.http.routers.minio-console.tls.certresolver=letsencrypt",
    "traefik.http.routers.minio-console.middlewares=authelia@consulcatalog",
  ]
  check {
    type     = "http"
    path     = "/minio/health/live"
    interval = "10s"
    timeout  = "2s"
  }
}

# S3 API service - UNPROTECTED (used by services, not humans)
service {
  name = "minio-api"
  port = "api"
  tags = [
    "storage",
    "s3-api",
    "traefik.enable=true",
    "traefik.http.routers.minio-api.rule=Host(`s3.lab.hartr.net`)",
    "traefik.http.routers.minio-api.entrypoints=websecure",
    "traefik.http.routers.minio-api.tls=true",
    "traefik.http.routers.minio-api.tls.certresolver=letsencrypt",
    # NO AUTHELIA - API needs direct access for services
  ]
  check {
    type     = "http"
    path     = "/minio/health/live"
    interval = "10s"
    timeout  = "2s"
  }
}
```

## Example 5: Docker Registry (Protect UI, Not Registry)

```hcl
# Registry service - UNPROTECTED (Docker needs direct access)
service {
  name = "docker-registry"
  port = "registry"
  tags = [
    "registry",
    "docker",
    "traefik.enable=true",
    "traefik.http.routers.docker-registry.rule=Host(`registry.lab.hartr.net`)",
    "traefik.http.routers.docker-registry.entrypoints=websecure",
    "traefik.http.routers.docker-registry.tls=true",
    "traefik.http.routers.docker-registry.tls.certresolver=letsencrypt",
    # No Authelia - Docker daemon needs direct access
  ]
}

# Registry UI - PROTECTED (web interface for humans)
service {
  name = "registry-ui"
  port = "ui"
  tags = [
    "registry-ui",
    "traefik.enable=true",
    "traefik.http.routers.registry-ui.rule=Host(`registry-ui.lab.hartr.net`)",
    "traefik.http.routers.registry-ui.entrypoints=websecure",
    "traefik.http.routers.registry-ui.tls=true",
    "traefik.http.routers.registry-ui.tls.certresolver=letsencrypt",
    "traefik.http.routers.registry-ui.middlewares=authelia@consulcatalog",
  ]
}
```

## Example 6: API Endpoints with Path-Based Rules

For services with specific API paths that should bypass auth:

```hcl
# Main app - PROTECTED
service {
  name = "myapp"
  port = "http"
  tags = [
    "traefik.enable=true",
    "traefik.http.routers.myapp.rule=Host(`myapp.lab.hartr.net`)",
    "traefik.http.routers.myapp.priority=1",
    "traefik.http.routers.myapp.entrypoints=websecure",
    "traefik.http.routers.myapp.tls=true",
    "traefik.http.routers.myapp.tls.certresolver=letsencrypt",
    "traefik.http.routers.myapp.middlewares=authelia@consulcatalog",
    
    # Public API endpoint - BYPASS AUTH
    "traefik.http.routers.myapp-api.rule=Host(`myapp.lab.hartr.net`) && PathPrefix(`/api`)",
    "traefik.http.routers.myapp-api.priority=2",
    "traefik.http.routers.myapp-api.entrypoints=websecure",
    "traefik.http.routers.myapp-api.tls=true",
    "traefik.http.routers.myapp-api.tls.certresolver=letsencrypt",
    # NO MIDDLEWARE - API accessible without auth
  ]
}
```

## Example 7: Webhooks and Callbacks

For services that receive webhooks (Gitea, Jenkins), create separate routes:

```hcl
tags = [
  "traefik.enable=true",
  
  # Main UI - PROTECTED
  "traefik.http.routers.gitea.rule=Host(`gitea.lab.hartr.net`)",
  "traefik.http.routers.gitea.priority=1",
  "traefik.http.routers.gitea.entrypoints=websecure",
  "traefik.http.routers.gitea.tls=true",
  "traefik.http.routers.gitea.tls.certresolver=letsencrypt",
  "traefik.http.routers.gitea.middlewares=authelia@consulcatalog",
  
  # Webhook endpoint - BYPASS AUTH
  "traefik.http.routers.gitea-webhook.rule=Host(`gitea.lab.hartr.net`) && PathPrefix(`/api/webhooks`)",
  "traefik.http.routers.gitea-webhook.priority=2",
  "traefik.http.routers.gitea-webhook.entrypoints=websecure",
  "traefik.http.routers.gitea-webhook.tls=true",
  "traefik.http.routers.gitea-webhook.tls.certresolver=letsencrypt",
]
```

## Protection Priority Tiers

### Tier 1: Always Protect (Infrastructure)
- Nomad UI
- Consul UI
- Vault UI
- Traefik Dashboard

### Tier 2: Protect (Monitoring)
- Grafana
- Prometheus
- Alertmanager
- Uptime Kuma

### Tier 3: Protect (Dev Tools)
- Jenkins
- Gitea
- Code Server
- Wiki

### Tier 4: Protect (Personal Services)
- Nextcloud
- Vaultwarden
- Calibre
- Audiobookshelf
- FreshRSS

### Tier 5: Conditional Protection
- MinIO Console: ✅ Protect
- MinIO S3 API: ❌ No protection (service-to-service)
- Docker Registry: ❌ No protection (Docker needs access)
- Docker Registry UI: ✅ Protect

### Bypass (Public Services)
- Homepage (landing page)
- Whoami (test service)
- Any webhook endpoints

## Testing Pattern

After adding middleware, test with curl:

```bash
# Should return 302 (redirect) for unauthenticated requests
curl -I https://grafana.lab.hartr.net

# Should see Location header pointing to Authelia
Location: https://authelia.lab.hartr.net/?rd=https://grafana.lab.hartr.net

# After login, should return 200
curl -I -b cookies.txt https://grafana.lab.hartr.net
```

## Quick Reference: Tag Order

Always maintain this order for consistency:

```hcl
tags = [
  # 1. Metadata tags (for Consul filtering)
  "service-type",
  "environment",
  
  # 2. Enable Traefik
  "traefik.enable=true",
  
  # 3. Router rule
  "traefik.http.routers.NAME.rule=Host(`example.lab.hartr.net`)",
  
  # 4. Entry point
  "traefik.http.routers.NAME.entrypoints=websecure",
  
  # 5. TLS
  "traefik.http.routers.NAME.tls=true",
  "traefik.http.routers.NAME.tls.certresolver=letsencrypt",
  
  # 6. Middleware (LAST)
  "traefik.http.routers.NAME.middlewares=authelia@consulcatalog",
]
```

## Common Mistakes to Avoid

❌ **Wrong provider**: `authelia@file` or `authelia@docker`
✅ **Correct**: `authelia@consulcatalog`

❌ **Multiple routers without priority**:
```hcl
"traefik.http.routers.app.rule=Host(`app.lab.hartr.net`)",
"traefik.http.routers.app-api.rule=Host(`app.lab.hartr.net`) && PathPrefix(`/api`)",
```
✅ **With priority**:
```hcl
"traefik.http.routers.app.rule=Host(`app.lab.hartr.net`)",
"traefik.http.routers.app.priority=1",
"traefik.http.routers.app-api.rule=Host(`app.lab.hartr.net`) && PathPrefix(`/api`)",
"traefik.http.routers.app-api.priority=2",
```

❌ **Health checks through auth**:
Make sure health check endpoints bypass auth or use TCP checks.

## Deployment Workflow

1. **Backup current job**:
   ```bash
   nomad job inspect SERVICE > backup-SERVICE.json
   ```

2. **Add middleware tag**:
   Edit `jobs/services/SERVICE.nomad.hcl`

3. **Deploy**:
   ```bash
   nomad job run jobs/services/SERVICE.nomad.hcl
   ```

4. **Test**:
   ```bash
   curl -I https://SERVICE.lab.hartr.net
   # Should see 302 redirect to Authelia
   ```

5. **Verify in browser**:
   - Open service URL
   - Should redirect to Authelia login
   - Login with credentials
   - Should redirect back to service

6. **Rollback if needed**:
   ```bash
   nomad job run backup-SERVICE.json
   ```

---

**Next**: See [AUTHELIA_SSO_IMPLEMENTATION.md](AUTHELIA_SSO_IMPLEMENTATION.md) for complete deployment guide.
