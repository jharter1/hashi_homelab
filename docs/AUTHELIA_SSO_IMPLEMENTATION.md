# Authelia SSO Implementation - Step-by-Step

**Quick implementation guide for deploying Authelia SSO across all homelab services.**

## Prerequisites Checklist

- [x] Authelia job deployed (`authelia.nomad.hcl`)
- [x] PostgreSQL database created for Authelia
- [x] Vault accessible for secrets storage
- [x] Traefik running and exposing services

## Step 1: Generate and Store Secrets

```bash
# Generate cryptographically secure secrets
JWT_SECRET=$(openssl rand -base64 48)
SESSION_SECRET=$(openssl rand -base64 48)
ENCRYPTION_KEY=$(openssl rand -base64 32)

# Store in Vault
export VAULT_ADDR=http://10.0.0.30:8200
vault kv put secret/authelia/config \
  jwt_secret="$JWT_SECRET" \
  session_secret="$SESSION_SECRET" \
  encryption_key="$ENCRYPTION_KEY"

# Verify storage
vault kv get secret/authelia/config
```

## Step 2: Create User Password Hash

```bash
# Generate Argon2 hash for your password
docker run --rm -it authelia/authelia:latest \
  authelia crypto hash generate argon2 --password 'YourStrongPassword123!'

# Copy the output hash (looks like: $argon2id$v=19$m=65536,t=3,p=4$...)
# You'll need this for the Authelia configuration
```

## Step 3: Update Authelia Job Configuration

Edit `jobs/services/authelia.nomad.hcl` with the updated configuration from the setup guide. Key changes:

1. Add Vault integration (`vault { policies = ["nomad-workloads"] }`)
2. Use Vault templates for secrets
3. Update users_database.yml with your password hash
4. Configure access control rules
5. Add ForwardAuth middleware tags

## Step 4: Deploy Redis (Session Storage)

```bash
# Create Redis job file if it doesn't exist
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

# Deploy Redis
nomad job run jobs/services/redis.nomad.hcl

# Verify deployment
nomad job status redis
consul catalog service redis
```

## Step 5: Deploy Updated Authelia

```bash
# Backup current Authelia job (if needed)
nomad job inspect authelia > authelia-backup.json

# Deploy updated Authelia
nomad job run jobs/services/authelia.nomad.hcl

# Watch deployment
nomad job status authelia

# Check logs for any errors
nomad alloc logs -f $(nomad job allocs authelia | grep running | awk '{print $1}' | head -1)
```

## Step 6: Test Authelia Login

```bash
# Check Authelia health
curl -I https://authelia.lab.hartr.net/api/health

# Should return: HTTP/2 200

# Visit in browser
open https://authelia.lab.hartr.net

# Login with:
# Username: jack
# Password: <your password from Step 2>
```

## Step 7: Protect Your First Service (Grafana)

### Option A: Quick Test with Whoami

```bash
# Update whoami.nomad.hcl to test auth
# Add middleware tag to service tags
```

Edit `jobs/services/whoami.nomad.hcl`:

```hcl
tags = [
  "traefik.enable=true",
  "traefik.http.routers.whoami.rule=Host(`whoami.lab.hartr.net`)",
  "traefik.http.routers.whoami.entrypoints=websecure",
  "traefik.http.routers.whoami.tls=true",
  "traefik.http.routers.whoami.tls.certresolver=letsencrypt",
  # ADD THIS LINE:
  "traefik.http.routers.whoami.middlewares=authelia@consulcatalog",
]
```

```bash
# Redeploy
nomad job run jobs/services/whoami.nomad.hcl

# Test - should redirect to Authelia login
curl -I https://whoami.lab.hartr.net
# Or visit in browser (incognito mode to test fresh session)
```

### Option B: Protect Grafana

Edit `jobs/services/grafana.nomad.hcl` and add middleware tag:

```bash
# Use multi_replace_string_in_file or manual edit
# Add: "traefik.http.routers.grafana.middlewares=authelia@consulcatalog"

nomad job run jobs/services/grafana.nomad.hcl
```

## Step 8: Bulk Protect All Services

Create a script to update all service jobs:

```bash
#!/usr/bin/env fish
# scripts/add-authelia-protection.fish

set services \
  prometheus \
  alertmanager \
  loki \
  jenkins \
  gitea \
  gollum \
  codeserver \
  uptime-kuma \
  calibre \
  audiobookshelf \
  freshrss \
  nextcloud \
  minio \
  docker-registry

for service in $services
  echo "Updating $service..."
  
  # This is a template - actual implementation would use sed or manual edits
  # Add middleware tag to each service's Traefik configuration
  
  # Redeploy
  nomad job run jobs/services/$service.nomad.hcl
  
  echo "✅ $service protected"
  sleep 2
end
```

## Step 9: Verify Protected Services

```bash
# Create a test script
cat > scripts/test-authelia-protection.fish <<'EOF'
#!/usr/bin/env fish

set services \
  grafana.lab.hartr.net \
  prometheus.lab.hartr.net \
  jenkins.lab.hartr.net \
  gitea.lab.hartr.net

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
EOF

chmod +x scripts/test-authelia-protection.fish
./scripts/test-authelia-protection.fish
```

## Step 10: Configure Groups and Access Levels

Update `users_database.yml` in Authelia config to add more users/groups:

```yaml
users:
  jack:
    displayname: "Jack Harter"
    password: "$argon2id$v=19$m=65536,t=3,p=4$YOUR_HASH_HERE"
    email: jack@hartr.net
    groups:
      - admins
      - users
  
  readonly_user:
    displayname: "Read Only User"
    password: "$argon2id$v=19$m=65536,t=3,p=4$DIFFERENT_HASH"
    email: readonly@lab.hartr.net
    groups:
      - users
```

Update access control rules for different group permissions:

```yaml
access_control:
  rules:
    # Admin-only services
    - domain:
        - vault.lab.hartr.net
        - nomad.lab.hartr.net
        - consul.lab.hartr.net
      policy: one_factor
      subject:
        - "group:admins"
    
    # Read-only monitoring for all users
    - domain:
        - grafana.lab.hartr.net
        - prometheus.lab.hartr.net
      policy: one_factor
      subject:
        - "group:users"
        - "group:admins"
```

## Step 11: Enable Two-Factor Authentication (Optional)

1. Login to Authelia at `https://authelia.lab.hartr.net`
2. Click on your username (top right)
3. Go to "Security" tab
4. Click "Register a One-Time Password device"
5. Scan QR code with authenticator app (Google Authenticator, Authy, etc.)
6. Enter verification code

Update access control for admin services to require 2FA:

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

## Step 12: Monitor and Maintain

```bash
# Check Authelia logs
nomad alloc logs -f $(nomad job allocs authelia | grep running | awk '{print $1}' | head -1)

# Check authentication attempts in logs
nomad alloc logs $(nomad job allocs authelia | grep running | awk '{print $1}' | head -1) | grep "Successful authentication"
nomad alloc logs $(nomad job allocs authelia | grep running | awk '{print $1}' | head -1) | grep "Failed authentication"

# View session storage in Redis
redis-cli -h redis.service.consul
> KEYS authelia-session:*
> GET authelia-session:YOUR_SESSION_ID
```

## Rollback Plan

If something goes wrong:

```bash
# 1. Remove middleware from affected services
# Edit job files to remove: "traefik.http.routers.SERVICE.middlewares=authelia@consulcatalog"

# 2. Redeploy services
for service in grafana prometheus jenkins; do
  nomad job run jobs/services/$service.nomad.hcl
done

# 3. Restore old Authelia config if needed
nomad job run authelia-backup.json

# 4. Services should be accessible again without auth
```

## Common Issues and Fixes

### Issue: Login loop (redirects back to login after successful auth)

```bash
# Check session cookie domain
nomad alloc logs $(nomad job allocs authelia | grep running | awk '{print $1}' | head -1) | grep "session.domain"

# Verify Redis is accessible
consul catalog service redis
redis-cli -h redis.service.consul PING

# Check browser cookies
# Should see: authelia_session cookie for .lab.hartr.net domain
```

### Issue: 502 Bad Gateway on protected services

```bash
# Verify Authelia is registered in Consul
consul catalog service authelia

# Test Authelia endpoint directly
curl http://authelia.service.consul:9091/api/verify

# Check Traefik can reach Authelia
nomad alloc exec -task traefik $(nomad job allocs traefik | grep running | awk '{print $1}' | head -1) \
  wget -O- http://authelia.service.consul:9091/api/health
```

### Issue: "Access Denied" after login

```bash
# Check access control rules in config
nomad alloc logs $(nomad job allocs authelia | grep running | awk '{print $1}' | head -1) | grep "access control"

# Verify user groups match access rules
# Edit users_database.yml and ensure user is in correct group
```

## Task Automation

Add to `Taskfile.yml`:

```yaml
authelia:deploy:
  desc: "Deploy Authelia with secrets from Vault"
  cmds:
    - |
      nomad job run jobs/services/authelia.nomad.hcl

authelia:test:
  desc: "Test Authelia protection on services"
  cmds:
    - |
      ./scripts/test-authelia-protection.fish

authelia:logs:
  desc: "Stream Authelia logs"
  cmds:
    - |
      nomad alloc logs -f $(nomad job allocs authelia | grep running | awk '{print $1}' | head -1)
```

## Success Checklist

- [ ] Secrets generated and stored in Vault
- [ ] Redis deployed for session storage
- [ ] Authelia updated with Vault integration
- [ ] Authelia deployed and accessible
- [ ] Test user can login at authelia.lab.hartr.net
- [ ] At least one service protected (whoami or grafana)
- [ ] Protected service redirects to Authelia login
- [ ] After login, protected service is accessible
- [ ] Session persists across browser restarts
- [ ] Logout works correctly
- [ ] Access control rules enforced properly

## Next Steps

After successful deployment:

1. **Document user onboarding** - How to create new users and reset passwords
2. **Setup email notifications** - Configure SMTP for password resets
3. **Enable monitoring** - Add Prometheus metrics for Authelia
4. **Backup strategy** - Regular backups of users_database.yml and Redis data
5. **Migrate to LDAP** (optional) - For enterprise-grade user management

---

**Estimated Time**: 30-45 minutes for basic setup  
**Complexity**: Intermediate

**Need Help?** Check the troubleshooting section or review Authelia logs for detailed error messages.
