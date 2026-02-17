# Authelia SSO - Unified Authentication Guide

**Last Updated**: February 15, 2026

> **Quick Reference**: For command shortcuts, see [CHEATSHEET.md](CHEATSHEET.md)

## Overview

Authelia provides Single Sign-On (SSO) authentication for all homelab services through Traefik ForwardAuth middleware. Login once, access everything.

### What You're Building

Transform this:
```
❌ Grafana → admin/admin
❌ Jenkins → separate login
❌ Gitea → different password
❌ Prometheus → no auth
```

Into this:
```
✅ All services → Single Authelia login
✅ Session persists across all apps
✅ One logout logs out everywhere
✅ 2FA option for admin tools
```

### Architecture

```
User → Traefik → Authelia (Auth Check) → Protected Service
                    ↓
                  Redis (Sessions)
                    ↓
              PostgreSQL (Storage)
```

**Authentication Flow:**
1. User requests `https://grafana.lab.hartr.net`
2. Traefik intercepts, sees ForwardAuth middleware
3. Traefik forwards auth request to Authelia at `/api/verify`
4. If not authenticated: Authelia redirects to login page
5. If authenticated: Authelia returns auth headers, Traefik proxies to service
6. User accesses service with SSO session

### Prerequisites

- [x] PostgreSQL running with `authelia` database
- [x] Vault accessible for secrets storage
- [x] Traefik exposing services via Consul Catalog
- [x] Redis deployed for session storage (optional but recommended)

---

## Quick Start (30 Minutes)

### 1. Generate Secrets (2 minutes)

```bash
export VAULT_ADDR=http://10.0.0.30:8200

vault kv put secret/authelia/config \
  jwt_secret="$(openssl rand -base64 48)" \
  session_secret="$(openssl rand -base64 48)" \
  encryption_key="$(openssl rand -base64 32)"
```

**Or use the automated script:**
```bash
./scripts/setup-authelia-secrets.fish
```

### 2. Create Your Password Hash (1 minute)

```bash
docker run --rm -it authelia/authelia:latest \
  authelia crypto hash generate argon2 --password 'YourStrongPassword123!'

# Copy the $argon2id$v=19$m=65536,t=3,p=4$... output
```

**Or use the script:**
```bash
./scripts/generate-authelia-password.fish
```

### 3. Update Authelia Configuration (2 minutes)

Edit `jobs/services/authelia.nomad.hcl` and replace the placeholder password hash in the `users_database.yml` template:

```yaml
users:
  jack:
    displayname: "Jack Harter"
    password: "$argon2id$PASTE_YOUR_HASH_HERE"  # ← Replace this
    email: jack@hartr.net
    groups:
      - admins
      - users
```

### 4. Deploy Services (5 minutes)

**Option A - Automated:**
```bash
./scripts/deploy-authelia-sso.fish
```

**Option B - Manual:**
```bash
# Deploy Redis (session storage)
nomad job run jobs/services/redis.nomad.hcl

# Wait for Redis to be healthy
sleep 10

# Deploy Authelia
nomad job run jobs/services/authelia.nomad.hcl

# Verify deployment
nomad job status authelia
curl https://authelia.lab.hartr.net/api/health
```

### 5. Test Login (2 minutes)

```bash
# Open Authelia
open https://authelia.lab.hartr.net

# Login with:
# Username: jack
# Password: <your password from step 2>
```

### 6. Protect Your First Service (5 minutes)

Edit `jobs/services/grafana.nomad.hcl` and add ONE line to the tags:

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
}
```

```bash
# Redeploy Grafana
nomad job run jobs/services/grafana.nomad.hcl

# Test (should redirect to Authelia)
open https://grafana.lab.hartr.net
```

**Success!** You now have working SSO authentication.

---

## Detailed Setup

### Step 1: Deploy Redis for Session Storage

Redis provides persistent session storage, allowing sessions to survive Authelia restarts.

```bash
# Create Redis job file (if it doesn't exist)
cat > jobs/services/redis.nomad.hcl <<'EOF'
job "redis" {
  datacenters = ["dc1"]
  type        = "service"

  group "redis" {
    count = 1

    network {
      mode = "host"
      port "redis" {
        static = 6379
      }
    }

    task "redis" {
      driver = "docker"

      config {
        image        = "redis:7-alpine"
        network_mode = "host"
        ports        = ["redis"]
        
        args = [
          "redis-server",
          "--appendonly", "yes",
          "--appendfsync", "everysec",
        ]
      }

      resources {
        cpu    = 100
        memory = 128
      }

      service {
        name = "redis"
        port = "redis"
        
        tags = [
          "cache",
          "session-store",
        ]

        check {
          type     = "tcp"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}
EOF

# Deploy
nomad job run jobs/services/redis.nomad.hcl
consul catalog service redis
```

### Step 2: Configure Authelia with Vault Integration

The Authelia job needs three critical components:
1. **Vault integration** (`vault {}` block) for secrets access
2. **Configuration template** with Vault secret injection
3. **Users database** with password hashes

See the reference configuration in `jobs/services/authelia.nomad.hcl`. Key sections:

**Vault Integration:**
```hcl
vault {
  policies = ["nomad-workloads"]
}
```

**Secret Injection:**
```hcl
template {
  destination = "local/configuration.yml"
  data        = <<EOH
jwt_secret: {{ with secret "secret/data/authelia/config" }}{{ .Data.data.jwt_secret }}{{ end }}
session:
  secret: {{ with secret "secret/data/authelia/config" }}{{ .Data.data.session_secret }}{{ end }}
storage:
  encryption_key: {{ with secret "secret/data/authelia/config" }}{{ .Data.data.encryption_key }}{{ end }}
EOH
}
```

**Session Configuration (with leading dot for cookie domain):**
```yaml
session:
  name: authelia_session
  domain: .lab.hartr.net  # Leading dot is CRITICAL for subdomain cookies
  expiration: 12h
  inactivity: 1h
  remember_me_duration: 1M
  
  redis:
    host: redis.service.consul
    port: 6379
```

**Access Control Rules:**
```yaml
access_control:
  default_policy: deny
  
  rules:
    # Bypass auth for Authelia itself
    - domain: authelia.lab.hartr.net
      policy: bypass
    
    # Protected services (require authentication)
    - domain:
        - grafana.lab.hartr.net
        - prometheus.lab.hartr.net
        - nomad.lab.hartr.net
        - consul.lab.hartr.net
      policy: one_factor
    
    # Admin-only services
    - domain:
        - vault.lab.hartr.net
      policy: one_factor
      subject:
        - "group:admins"
```

### Step 3: Configure Traefik Middleware

Authelia registers its ForwardAuth middleware via Consul Catalog service tags:

```hcl
tags = [
  "traefik.http.middlewares.authelia.forwardauth.address=http://authelia.service.consul:9091/api/verify?rd=https://authelia.lab.hartr.net",
  "traefik.http.middlewares.authelia.forwardauth.trustForwardHeader=true",
  "traefik.http.middlewares.authelia.forwardauth.authResponseHeaders=Remote-User,Remote-Groups,Remote-Name,Remote-Email",
]
```

This makes the `authelia@consulcatalog` middleware available to all services.

---

## Protecting Services

### Basic Protection Pattern

Add **one line** to any service's Traefik tags:

```hcl
"traefik.http.routers.SERVICE_NAME.middlewares=authelia@consulcatalog"
```

### Example 1: Prometheus (Simple)

**Before:**
```hcl
tags = [
  "traefik.enable=true",
  "traefik.http.routers.prometheus.rule=Host(`prometheus.lab.hartr.net`)",
  "traefik.http.routers.prometheus.entrypoints=websecure",
  "traefik.http.routers.prometheus.tls=true",
  "traefik.http.routers.prometheus.tls.certresolver=letsencrypt",
]
```

**After:**
```hcl
tags = [
  "traefik.enable=true",
  "traefik.http.routers.prometheus.rule=Host(`prometheus.lab.hartr.net`)",
  "traefik.http.routers.prometheus.entrypoints=websecure",
  "traefik.http.routers.prometheus.tls=true",
  "traefik.http.routers.prometheus.tls.certresolver=letsencrypt",
  "traefik.http.routers.prometheus.middlewares=authelia@consulcatalog",
]
```

### Example 2: MinIO (Selective Protection)

Protect the web console but leave the S3 API open for service-to-service communication:

```hcl
# Console service (Web UI) - PROTECTED
service {
  name = "minio-console"
  port = "console"
  tags = [
    "traefik.enable=true",
    "traefik.http.routers.minio-console.rule=Host(`minio.lab.hartr.net`)",
    "traefik.http.routers.minio-console.entrypoints=websecure",
    "traefik.http.routers.minio-console.tls=true",
    "traefik.http.routers.minio-console.tls.certresolver=letsencrypt",
    "traefik.http.routers.minio-console.middlewares=authelia@consulcatalog",
  ]
}

# S3 API service - UNPROTECTED (services need direct access)
service {
  name = "minio-api"
  port = "api"
  tags = [
    "traefik.enable=true",
    "traefik.http.routers.minio-api.rule=Host(`s3.lab.hartr.net`)",
    "traefik.http.routers.minio-api.entrypoints=websecure",
    "traefik.http.routers.minio-api.tls=true",
    "traefik.http.routers.minio-api.tls.certresolver=letsencrypt",
    # No middleware - API accessible without auth
  ]
}
```

### Example 3: Path-Based Bypass (API Endpoints)

For services with specific API paths that need to bypass auth:

```hcl
service {
  name = "calibre"
  port = "http"
  tags = [
    "traefik.enable=true",
    
    # Main UI - PROTECTED
    "traefik.http.routers.calibre.rule=Host(`calibre.lab.hartr.net`)",
    "traefik.http.routers.calibre.priority=1",
    "traefik.http.routers.calibre.entrypoints=websecure",
    "traefik.http.routers.calibre.tls=true",
    "traefik.http.routers.calibre.tls.certresolver=letsencrypt",
    "traefik.http.routers.calibre.middlewares=authelia@consulcatalog",
    
    # OPDS API - BYPASS AUTH (for e-readers)
    "traefik.http.routers.calibre-opds.rule=Host(`calibre.lab.hartr.net`) && PathPrefix(`/opds`)",
    "traefik.http.routers.calibre-opds.priority=2",
    "traefik.http.routers.calibre-opds.entrypoints=websecure",
    "traefik.http.routers.calibre-opds.tls=true",
    "traefik.http.routers.calibre-opds.tls.certresolver=letsencrypt",
    # No middleware - API accessible without auth
  ]
}
```

### What to Protect

**Tier 1 - Critical Infrastructure** (protect first):
- ✅ Nomad UI
- ✅ Consul UI  
- ✅ Vault UI
- ✅ Traefik Dashboard

**Tier 2 - Monitoring Stack**:
- ✅ Grafana
- ✅ Prometheus
- ✅ Alertmanager
- ✅ Uptime Kuma
- ✅ Loki

**Tier 3 - Development Tools**:
- ✅ Jenkins
- ✅ Code Server
- ✅ Wiki

**Tier 4 - Personal Services**:
- ✅ Calibre
- ✅ Audiobookshelf
- ✅ FreshRSS

**Tier 5 - Storage/Registry** (selective):
- ✅ MinIO Console
- ❌ MinIO S3 API (services need access)
- ✅ Docker Registry UI
- ❌ Docker Registry API (Docker needs access)

**Don't Protect** (have their own auth):
- ❌ Speedtest Tracker (Laravel Filament auth)
- ❌ Gitea (full user management)
- ❌ Nextcloud (enterprise auth system)

**Keep Public**:
- ❌ Homepage (landing page)
- ❌ Whoami (test service)

---

## Troubleshooting

### Login Loop (Keeps Redirecting)

**Symptoms:**
- Users redirected to login page repeatedly
- Credentials accepted but session doesn't persist
- Logs show `<anonymous>` user for all requests

**Most Common Cause: Wrong ForwardAuth Endpoint**

Authelia's API endpoint is `/api/verify?rd=...`, not the old `/api/authz/forward-auth`:

```yaml
# CORRECT configuration:
http:
  middlewares:
    authelia:
      forwardAuth:
        address: http://authelia.service.consul:9091/api/verify?rd=https://authelia.lab.hartr.net
        trustForwardHeader: true
```

**Verify Traefik middleware:**
```bash
nomad alloc exec -task traefik $(nomad job status traefik | grep running | awk '{print $1}' | head -1) \
  cat /etc/traefik/dynamic.yml | grep -A 5 authelia
```

**Second Cause: Cookie Domain Missing Leading Dot**

Session cookies must have a leading dot to work across subdomains:

```yaml
session:
  domain: .lab.hartr.net  # ✅ CORRECT - works for *.lab.hartr.net
  # NOT: lab.hartr.net   # ❌ WRONG - only works for exact domain
```

**Check browser cookies:**
1. Open DevTools → Application → Cookies
2. `authelia_session` cookie should show Domain: `.lab.hartr.net` (with leading dot)
3. Cookie should be sent to all protected services

**Third Cause: Redis Session Store Unavailable**

```bash
# Test Redis connectivity
consul catalog service redis
redis-cli -h redis.service.consul PING

# Test from Authelia container
ALLOC_ID=$(nomad job status authelia | grep running | awk '{print $1}' | head -1)
nomad alloc exec $ALLOC_ID redis-cli -h redis.service.consul PING
```

### API Endpoints Return 401 Unauthorized

**Problem:** Services with their own API authentication (like Calibre's OPDS API or Grafana's `/api/*` endpoints) return 401 errors or redirect to Authelia.

**Cause:** Authelia protects ALL paths by default, including API endpoints with their own auth schemes.

**Solution:** Add path-based bypass rules in Authelia's `access_control` section:

```yaml
access_control:
  rules:
    # Add BEFORE general domain rules
    
    # Calibre OPDS API
    - domain:
        - calibre.lab.hartr.net
      resources:
        - "^/opds.*$"
      policy: bypass
    
    # Grafana APIs
    - domain:
        - grafana.lab.hartr.net
      resources:
        - "^/api/.*$"
        - "^/avatar/.*$"
        - "^/public/.*$"
      policy: bypass
    
    # Then your regular protection rules
    - domain:
        - calibre.lab.hartr.net
        - grafana.lab.hartr.net
      policy: one_factor
```

**Verify:**
```bash
# API should return 200
curl -I https://calibre.lab.hartr.net/opds/stats

# Web UI should still redirect (302)
curl -I https://calibre.lab.hartr.net/
```

### SSO Works But Services Show Anonymous User

**Symptom:** After logging into Authelia, protected services still show anonymous/unauthenticated user.

**Cause:** Cookie domain doesn't have leading dot, preventing browser from sending cookie to subdomains.

**Solution:** Update session domain in `authelia.nomad.hcl`:

```hcl
session:
  domain: .lab.hartr.net  # Leading dot is CRITICAL
```

**Why this matters:**
- Without leading dot: Cookie only valid for `authelia.lab.hartr.net`
- With leading dot: Cookie valid for all `*.lab.hartr.net` subdomains
- Browser RFC 6265 requires leading dot for subdomain sharing

### 502 Bad Gateway on Protected Services

```bash
# Verify Authelia is registered in Consul
consul catalog service authelia

# Test Authelia endpoint directly
curl http://authelia.service.consul:9091/api/verify
curl http://authelia.service.consul:9091/api/health

# Test from Traefik container
nomad alloc exec -task traefik $(nomad job allocs traefik | grep running | awk '{print $1}' | head -1) \
  wget -O- http://authelia.service.consul:9091/api/health
```

### "Access Denied" After Login

```bash
# Check access control rules and user groups
nomad alloc logs $(nomad job allocs authelia | grep running | awk '{print $1}' | head -1) | grep "access denied"

# Verify user is in correct group
# Edit jobs/services/authelia.nomad.hcl users_database.yml section
# User's groups must match the access control rule's subject
```

### Double Authentication on Some Services

**Problem:** Services like Speedtest Tracker, Gitea, or Nextcloud have their own robust authentication. Adding Authelia creates confusing double-login.

**Solution:** Don't protect these services with Authelia. Remove the middleware tag:

```hcl
# DON'T do this for apps with built-in auth:
service {
  tags = [
    "traefik.enable=true",
    "traefik.http.routers.speedtest.rule=Host(`speedtest.lab.hartr.net`)",
    # "traefik.http.routers.speedtest.middlewares=authelia@consulcatalog",  # ❌ REMOVE
  ]
}
```

**Apps That Should NOT Use Authelia:**
- Speedtest Tracker (Laravel Filament auth)
- Gitea (full user management with 2FA, OAuth, LDAP)
- Nextcloud (enterprise user management)
- Vault (token-based auth)

**Apps That SHOULD Use Authelia:**
- Grafana (can use forward auth headers)
- Prometheus (no built-in auth)
- Alertmanager (basic or no auth)
- Traefik Dashboard (basic or no auth)

---

## Advanced Configuration

### Add More Users

Edit `jobs/services/authelia.nomad.hcl`, add to the `users_database.yml` template:

```yaml
users:
  jack:
    displayname: "Jack Harter"
    password: "$argon2id$YOUR_HASH"
    email: jack@hartr.net
    groups:
      - admins
      - users
  
  newuser:
    displayname: "New User"
    password: "$argon2id$DIFFERENT_HASH"
    email: newuser@lab.hartr.net
    groups:
      - users  # Or 'admins' for admin access
```

Generate password hash:
```bash
./scripts/generate-authelia-password.fish
```

Redeploy:
```bash
nomad job run jobs/services/authelia.nomad.hcl
```

### Enable Two-Factor Authentication

**Setup for users:**
1. Login to Authelia at `https://authelia.lab.hartr.net`
2. Click username → Settings
3. Security → Register One-Time Password
4. Scan QR code with authenticator app
5. Enter verification code

**Require 2FA for admin services:**

Update access control in `authelia.nomad.hcl`:
```yaml
access_control:
  rules:
    - domain:
        - vault.lab.hartr.net
        - nomad.lab.hartr.net
        - consul.lab.hartr.net
      policy: two_factor  # Changed from one_factor
      subject:
        - "group:admins"
```

### Setup Email Notifications

Edit `jobs/services/authelia.nomad.hcl`, configure SMTP:

```yaml
notifier:
  smtp:
    host: smtp.gmail.com
    port: 587
    username: your-email@gmail.com
    password: {{ with secret "secret/data/smtp/gmail" }}{{ .Data.data.app_password }}{{ end }}
    sender: "Authelia <authelia@lab.hartr.net>"
    subject: "[Authelia] {title}"
```

Store SMTP credentials in Vault:
```bash
vault kv put secret/smtp/gmail app_password="your-app-password"
```

### Group-Based Access Control

Create different access levels:

```yaml
access_control:
  rules:
    # Admin-only services
    - domain:
        - vault.lab.hartr.net
        - nomad.lab.hartr.net
      policy: one_factor
      subject:
        - "group:admins"
    
    # Read-only monitoring for all authenticated users
    - domain:
        - grafana.lab.hartr.net
        - prometheus.lab.hartr.net
      policy: one_factor
      subject:
        - "group:users"
        - "group:admins"
    
    # Personal services - user-specific access
    - domain:
        - nextcloud.lab.hartr.net
      policy: one_factor
      subject:
        - "user:jack"
```

### LDAP/Active Directory Integration

For larger deployments, replace file-based auth:

```yaml
authentication_backend:
  ldap:
    url: ldap://ldap.service.consul:389
    base_dn: dc=lab,dc=hartr,dc=net
    username_attribute: uid
    additional_users_dn: ou=users
    users_filter: (&({username_attribute}={input})(objectClass=person))
    additional_groups_dn: ou=groups
    groups_filter: (&(member={dn})(objectClass=groupOfNames))
    user: cn=admin,dc=lab,dc=hartr,dc=net
    password: {{ with secret "secret/data/ldap/admin" }}{{ .Data.data.password }}{{ end }}
```

---

## Testing & Verification

### Quick Test Script

```bash
#!/usr/bin/env fish
# scripts/test-authelia-protection.fish

set services \
  grafana.lab.hartr.net \
  prometheus.lab.hartr.net \
  jenkins.lab.hartr.net

echo "Testing Authelia protection..."
echo ""

for service in $services
  echo "Testing $service..."
  set status (curl -s -o /dev/null -w "%{http_code}" -L https://$service)
  
  if test $status -eq 200
    echo "  ❌ UNPROTECTED - Returns 200 (should redirect)"
  else if test $status -eq 302
    echo "  ✅ PROTECTED - Returns 302 (redirect to Authelia)"
  else
    echo "  ⚠️  UNKNOWN - Returns $status"
  end
end
```

### Verification Checklist

After deployment:

- [ ] Secrets stored in Vault: `vault kv get secret/authelia/config`
- [ ] Redis running: `nomad job status redis`
- [ ] Authelia running: `nomad job status authelia`
- [ ] Authelia healthy: `curl https://authelia.lab.hartr.net/api/health`
- [ ] Login page accessible: `open https://authelia.lab.hartr.net`
- [ ] Can login with credentials
- [ ] Protected service redirects to Authelia
- [ ] After login, service is accessible
- [ ] Session persists (visit other services without re-login)
- [ ] Logout works correctly

### Monitor Authentication

```bash
# View Authelia logs
nomad alloc logs -f $(nomad job allocs authelia | grep running | awk '{print $1}' | head -1)

# Check successful logins
nomad alloc logs $(nomad job allocs authelia | grep running | awk '{print $1}' | head -1) | grep "Successful"

# Check failed attempts
nomad alloc logs $(nomad job allocs authelia | grep running | awk '{print $1}' | head -1) | grep "Failed"

# View session data in Redis
redis-cli -h redis.service.consul KEYS "authelia-session:*"
```

---

## Rollback Plan

If something goes wrong:

```bash
# 1. Backup current state
nomad job inspect authelia > authelia-backup.json

# 2. Remove middleware from affected services
# Edit job files to remove: "traefik.http.routers.SERVICE.middlewares=authelia@consulcatalog"

# 3. Redeploy services
for service in grafana prometheus jenkins; do
  nomad job run jobs/services/$service.nomad.hcl
done

# 4. Restore old Authelia config if needed
nomad job run authelia-backup.json

# 5. Services should be accessible again without auth
```

---

## Security Best Practices

1. **Use Strong Secrets**: All JWT, session, and encryption keys should be cryptographically random (48+ bytes)
2. **Enable HTTPS Only**: Never expose Authelia or services over HTTP
3. **Implement 2FA**: Require two-factor auth for admin services
4. **Regular Backups**: Backup PostgreSQL database and user configurations
5. **Monitor Auth Logs**: Set up alerts for failed login attempts
6. **Session Timeouts**: Configure appropriate expiration (default: 12h)
7. **Rate Limiting**: Current config: max 5 failed attempts, 10min ban
8. **Secure Cookies**: Authelia automatically sets secure, httpOnly cookies

---

## Estimated Times

- **Quick Setup**: 30 minutes
- **Protect 5 services**: +15 minutes
- **Protect all services**: +30 minutes
- **Enable 2FA**: +5 minutes per user
- **Setup email**: +15 minutes

**Total to full SSO**: 1-2 hours

---

## References

- [Authelia Documentation](https://www.authelia.com/docs/)
- [Traefik ForwardAuth Middleware](https://doc.traefik.io/traefik/middlewares/http/forwardauth/)
- [Authelia Traefik Integration](https://www.authelia.com/integration/proxies/traefik/)
- [Argon2 Password Hashing](https://www.authelia.com/reference/guides/passwords/)
- **Quick Commands**: See [CHEATSHEET.md](CHEATSHEET.md)
