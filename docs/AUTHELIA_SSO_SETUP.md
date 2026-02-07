# Authelia SSO Integration Guide

**Last Updated**: February 6, 2026

## Overview

This guide explains how to use Authelia as a unified Single Sign-On (SSO) solution for all services in your HashiCorp homelab. Authelia sits in front of Traefik and provides authentication before users can access protected services.

## Architecture

```
User → Traefik → Authelia (Auth Check) → Protected Service
                    ↓
              PostgreSQL (User DB)
```

**Flow:**
1. User requests `https://grafana.lab.hartr.net`
2. Traefik intercepts request, sees ForwardAuth middleware
3. Traefik forwards auth request to Authelia
4. If not authenticated: Authelia redirects to login page
5. If authenticated: Authelia returns auth headers, Traefik proxies to service
6. User accesses service with SSO session

## Current Setup Status

✅ **Deployed**: Authelia running at `https://authelia.lab.hartr.net`  
✅ **Database**: PostgreSQL database created for user storage  
⚠️ **Configuration**: Using basic file-based auth (needs upgrade to PostgreSQL)  
❌ **Service Integration**: Not yet protecting any services  

## Implementation Steps

### Phase 1: Secure Authelia Configuration

The current configuration uses placeholder secrets. These need to be replaced with secure, random values.

#### 1.1 Generate Secrets

```bash
# Generate secrets (run on your local machine)
JWT_SECRET=$(openssl rand -base64 48)
SESSION_SECRET=$(openssl rand -base64 48)
ENCRYPTION_KEY=$(openssl rand -base64 32)

# Store in Vault (recommended)
vault kv put secret/authelia/config \
  jwt_secret="$JWT_SECRET" \
  session_secret="$SESSION_SECRET" \
  encryption_key="$ENCRYPTION_KEY"

# Or store in Nomad variables
nomad var put nomad/jobs/authelia \
  jwt_secret="$JWT_SECRET" \
  session_secret="$SESSION_SECRET" \
  encryption_key="$ENCRYPTION_KEY"
```

#### 1.2 Upgrade to PostgreSQL Backend

Replace file-based authentication with PostgreSQL for better scalability and management.

**Benefits:**
- Centralized user management
- Better performance at scale
- Integration with other services
- Easier backup/restore

See updated `jobs/services/authelia.nomad.hcl` in Phase 3 implementation.

### Phase 2: Configure Traefik Middleware

Traefik needs an Authelia ForwardAuth middleware to protect services.

#### 2.1 Add Authelia Middleware to Traefik

Update `jobs/system/traefik.nomad.hcl` to include Authelia middleware configuration in the static config:

```yaml
# Add to traefik.yml template
http:
  middlewares:
    authelia:
      forwardAuth:
        address: http://authelia.service.consul:9091/api/verify?rd=https://authelia.lab.hartr.net
        trustForwardHeader: true
        authResponseHeaders:
          - Remote-User
          - Remote-Groups
          - Remote-Name
          - Remote-Email
```

**Note**: This will be configured via dynamic config (file provider) - see Phase 3.

### Phase 3: Update Authelia Job (PostgreSQL + Secrets)

Here's the updated Authelia job with PostgreSQL backend and Vault integration:

```hcl
job "authelia" {
  datacenters = ["dc1"]
  type        = "service"

  group "authelia" {
    count = 1

    network {
      mode = "host"
      port "http" {
        static = 9091
      }
    }

    volume "authelia_data" {
      type      = "host"
      read_only = false
      source    = "authelia_data"
    }

    task "authelia" {
      driver = "docker"

      vault {
        policies = ["nomad-workloads"]
      }

      config {
        image        = "authelia/authelia:latest"
        network_mode = "host"
        ports        = ["http"]

        volumes = [
          "local/configuration.yml:/config/configuration.yml:ro",
        ]
      }

      volume_mount {
        volume      = "authelia_data"
        destination = "/data"
      }

      template {
        destination = "local/configuration.yml"
        data        = <<EOH
server:
  host: 0.0.0.0
  port: 9091
  path: ""
  read_buffer_size: 4096
  write_buffer_size: 4096

log:
  level: info
  format: text

jwt_secret: {{ with secret "secret/data/authelia/config" }}{{ .Data.data.jwt_secret }}{{ end }}
default_redirection_url: https://home.lab.hartr.net

authentication_backend:
  password_reset:
    disable: false
  
  file:
    path: /config/users_database.yml
    password:
      algorithm: argon2id
      iterations: 3
      salt_length: 16
      parallelism: 4
      memory: 64

access_control:
  default_policy: deny
  
  rules:
    # Bypass auth for Authelia itself
    - domain: authelia.lab.hartr.net
      policy: bypass
    
    # Public services (no auth required)
    - domain:
        - home.lab.hartr.net
        - whoami.lab.hartr.net
      policy: bypass
    
    # Protected services (require authentication)
    - domain:
        - grafana.lab.hartr.net
        - prometheus.lab.hartr.net
        - alertmanager.lab.hartr.net
        - loki.lab.hartr.net
        - jenkins.lab.hartr.net
        - gitea.lab.hartr.net
        - wiki.lab.hartr.net
        - code.lab.hartr.net
        - uptime-kuma.lab.hartr.net
        - calibre.lab.hartr.net
        - audiobookshelf.lab.hartr.net
        - freshrss.lab.hartr.net
        - nextcloud.lab.hartr.net
        - minio.lab.hartr.net
        - s3.lab.hartr.net
        - registry.lab.hartr.net
        - registry-ui.lab.hartr.net
        - nomad.lab.hartr.net
        - consul.lab.hartr.net
        - vault.lab.hartr.net
        - traefik.lab.hartr.net
      policy: one_factor
    
    # Admin-only services (future: two_factor)
    - domain:
        - vault.lab.hartr.net
        - nomad.lab.hartr.net
        - consul.lab.hartr.net
      policy: one_factor
      subject:
        - "group:admins"

session:
  name: authelia_session
  secret: {{ with secret "secret/data/authelia/config" }}{{ .Data.data.session_secret }}{{ end }}
  expiration: 12h
  inactivity: 1h
  remember_me_duration: 1M
  domain: lab.hartr.net
  
  redis:
    host: redis.service.consul
    port: 6379

regulation:
  max_retries: 5
  find_time: 2m
  ban_time: 10m

storage:
  encryption_key: {{ with secret "secret/data/authelia/config" }}{{ .Data.data.encryption_key }}{{ end }}
  
  postgres:
    host: postgresql.service.consul
    port: 5432
    database: authelia
    username: authelia
    password: {{ with secret "secret/data/postgres/authelia" }}{{ .Data.data.password }}{{ end }}

notifier:
  disable_startup_check: false
  filesystem:
    filename: /data/notification.txt

# Optional: SMTP for real email notifications
# notifier:
#   smtp:
#     host: smtp.gmail.com
#     port: 587
#     username: your-email@gmail.com
#     password: your-app-password
#     sender: Authelia <authelia@lab.hartr.net>
EOH
      }

      # User database (file-based for now, migrate to LDAP/PostgreSQL later)
      template {
        destination = "local/users_database.yml"
        data        = <<EOH
users:
  jack:
    displayname: "Jack Harter"
    password: "$argon2id$v=19$m=65536,t=3,p=4$CHANGE_THIS_HASH"
    email: jack@hartr.net
    groups:
      - admins
      - users

# Generate password hash with:
# docker run --rm authelia/authelia:latest authelia crypto hash generate argon2 --password 'YOUR_PASSWORD'
EOH
      }

      resources {
        cpu    = 200
        memory = 256
      }

      service {
        name = "authelia"
        port = "http"
        tags = [
          "security",
          "authentication",
          "sso",
          "traefik.enable=true",
          "traefik.http.routers.authelia.rule=Host(`authelia.lab.hartr.net`)",
          "traefik.http.routers.authelia.entrypoints=websecure",
          "traefik.http.routers.authelia.tls=true",
          "traefik.http.routers.authelia.tls.certresolver=letsencrypt",
          # Define the ForwardAuth middleware
          "traefik.http.middlewares.authelia.forwardauth.address=http://authelia.service.consul:9091/api/verify?rd=https://authelia.lab.hartr.net",
          "traefik.http.middlewares.authelia.forwardauth.trustForwardHeader=true",
          "traefik.http.middlewares.authelia.forwardauth.authResponseHeaders=Remote-User,Remote-Groups,Remote-Name,Remote-Email",
        ]
        check {
          type     = "http"
          path     = "/api/health"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}
```

### Phase 4: Protect Services with Authelia

To protect a service, add the Authelia middleware to its Traefik tags:

#### Example: Protect Grafana

```hcl
tags = [
  "traefik.enable=true",
  "traefik.http.routers.grafana.rule=Host(`grafana.lab.hartr.net`)",
  "traefik.http.routers.grafana.entrypoints=websecure",
  "traefik.http.routers.grafana.tls=true",
  "traefik.http.routers.grafana.tls.certresolver=letsencrypt",
  # ADD THIS LINE:
  "traefik.http.routers.grafana.middlewares=authelia@consulcatalog",
]
```

#### Services to Protect

**Tier 1 - Critical Infrastructure** (protect first):
- ✅ Nomad UI (`nomad.lab.hartr.net`)
- ✅ Consul UI (`consul.lab.hartr.net`)
- ✅ Vault UI (`vault.lab.hartr.net`)
- ✅ Traefik Dashboard (`traefik.lab.hartr.net`)

**Tier 2 - Monitoring Stack**:
- ✅ Grafana (`grafana.lab.hartr.net`)
- ✅ Prometheus (`prometheus.lab.hartr.net`)
- ✅ Alertmanager (`alertmanager.lab.hartr.net`)
- ✅ Uptime Kuma (`uptime-kuma.lab.hartr.net`)

**Tier 3 - Development Tools**:
- ✅ Gitea (`gitea.lab.hartr.net`)
- ✅ Jenkins (`jenkins.lab.hartr.net`)
- ✅ Code Server (`code.lab.hartr.net`)
- ✅ Wiki (`wiki.lab.hartr.net`)

**Tier 4 - Personal Services**:
- ✅ Nextcloud (`nextcloud.lab.hartr.net`)
- ✅ Vaultwarden (`vaultwarden.lab.hartr.net`)
- ✅ Calibre (`calibre.lab.hartr.net`)
- ✅ Audiobookshelf (`audiobookshelf.lab.hartr.net`)
- ✅ FreshRSS (`freshrss.lab.hartr.net`)

**Tier 5 - Storage/Registry**:
- ✅ MinIO Console (`minio.lab.hartr.net`)
- ✅ S3 API (`s3.lab.hartr.net`)
- ✅ Docker Registry UI (`registry-ui.lab.hartr.net`)

**Bypass (Public)**:
- ❌ Homepage (`home.lab.hartr.net`) - main landing page
- ❌ Whoami (`whoami.lab.hartr.net`) - test service

### Phase 5: Deploy and Test

```bash
# 1. Store secrets in Vault
vault kv put secret/authelia/config \
  jwt_secret="$(openssl rand -base64 48)" \
  session_secret="$(openssl rand -base64 48)" \
  encryption_key="$(openssl rand -base64 32)"

# 2. Generate password hash for your user
docker run --rm authelia/authelia:latest \
  authelia crypto hash generate argon2 --password 'YourStrongPassword'

# 3. Update Authelia job with the hash in users_database.yml

# 4. Deploy updated Authelia
nomad job run jobs/services/authelia.nomad.hcl

# 5. Test authentication
curl -I https://authelia.lab.hartr.net
# Should return 200 OK

# 6. Update and redeploy a test service (e.g., Grafana)
nomad job run jobs/services/grafana.nomad.hcl

# 7. Visit https://grafana.lab.hartr.net
# Should redirect to Authelia login
```

## Advanced Configuration

### Redis Session Storage (Optional)

For better session management, deploy Redis:

```bash
nomad job run jobs/services/redis.nomad.hcl
```

Then update Authelia config to use Redis instead of in-memory sessions (already shown in Phase 3 config above).

### Two-Factor Authentication

Add TOTP support for admin services:

1. Update access control rules to require `two_factor` for admin domains
2. Users configure TOTP in Authelia UI under their profile
3. Enforce 2FA for sensitive services

### LDAP/Active Directory Integration

For larger deployments, replace file-based auth with LDAP:

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
    group_name_attribute: cn
    mail_attribute: mail
    display_name_attribute: displayName
    user: cn=admin,dc=lab,dc=hartr,dc=net
    password: {{ with secret "secret/data/ldap/admin" }}{{ .Data.data.password }}{{ end }}
```

### Email Notifications

Configure SMTP for password reset and security alerts:

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

## Troubleshooting

### Issue: Redirect loop after login

**Cause**: Session cookies not working across domains  
**Solution**: Verify `session.domain: lab.hartr.net` in config matches your domain

### Issue: "Access Denied" after successful login

**Cause**: Access control rules blocking user  
**Solution**: Check Authelia logs and verify user is in correct group

```bash
nomad alloc logs -f <authelia-alloc-id>
```

### Issue: Services still accessible without auth

**Cause**: Middleware not applied correctly  
**Solution**: Verify Traefik tags include `middlewares=authelia@consulcatalog`

```bash
# Check Traefik configuration
curl http://traefik.lab.hartr.net/api/http/routers | jq .
```

### Issue: 502 Bad Gateway on protected services

**Cause**: Authelia service not reachable from Traefik  
**Solution**: Verify Authelia is registered in Consul

```bash
consul catalog services | grep authelia
curl http://authelia.service.consul:9091/api/health
```

## Security Best Practices

1. **Use Strong Secrets**: All JWT, session, and encryption keys should be cryptographically random (48+ bytes)
2. **Enable HTTPS Only**: Never expose Authelia or services over HTTP
3. **Implement 2FA**: Require two-factor auth for admin services (Vault, Nomad, Consul)
4. **Regular Backups**: Backup PostgreSQL database and user configurations
5. **Monitor Auth Logs**: Set up alerts for failed login attempts
6. **Session Timeouts**: Configure appropriate session expiration (currently 12h)
7. **Rate Limiting**: Current config: max 5 failed attempts, 10min ban
8. **Secure Cookies**: Authelia automatically sets secure, httpOnly cookies

## Migration Path

**Current State**: File-based auth with placeholder secrets  
**Next Steps**:
1. ✅ Generate and store real secrets in Vault
2. ✅ Update Authelia job with Vault integration
3. ✅ Test with one service (Grafana)
4. ⏭️ Roll out to Tier 1 services (infrastructure)
5. ⏭️ Roll out to remaining services
6. ⏭️ Deploy Redis for session storage
7. ⏭️ Enable 2FA for admin accounts
8. ⏭️ Configure email notifications (optional)

## References

- [Authelia Documentation](https://www.authelia.com/docs/)
- [Traefik ForwardAuth Middleware](https://doc.traefik.io/traefik/middlewares/http/forwardauth/)
- [Authelia Traefik Integration](https://www.authelia.com/integration/proxies/traefik/)
- [Argon2 Password Hashing](https://www.authelia.com/reference/guides/passwords/)

---

**Next**: See `AUTHELIA_SSO_IMPLEMENTATION.md` for step-by-step deployment commands.
