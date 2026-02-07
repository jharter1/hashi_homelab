# Authelia SSO - Ready to Deploy! 🚀

All configuration files are prepared. Follow these steps to deploy unified authentication across your homelab.

## What's Ready

- ✅ **Authelia Job** - Updated with Vault integration, Redis sessions, and access control
- ✅ **Redis Job** - For persistent session storage
- ✅ **Grafana Example** - Already configured with Authelia protection
- ✅ **Setup Scripts** - Automated secret generation and deployment
- ✅ **Test Scripts** - Verify protection is working

## Deployment Steps

### 1. Generate Secrets (2 minutes)

```bash
./scripts/setup-authelia-secrets.fish
```

This generates and stores three cryptographic secrets in Vault:
- JWT secret (48 bytes)
- Session secret (48 bytes)
- Encryption key (32 bytes)

### 2. Generate Your Password Hash (1 minute)

```bash
./scripts/generate-authelia-password.fish
```

When prompted, enter your password. Copy the `$argon2id$...` hash from the output.

### 3. Update Authelia Configuration (1 minute)

Edit `jobs/services/authelia.nomad.hcl` and replace the placeholder password hash:

```yaml
users:
  jack:
    displayname: "Jack Harter"
    password: "$argon2id$PASTE_YOUR_HASH_HERE"
    email: jack@hartr.net
    groups:
      - admins
      - users
```

### 4. Deploy Everything (3 minutes)

Option A - Use the automated script:
```bash
./scripts/deploy-authelia-sso.fish
```

Option B - Deploy manually:
```bash
# Deploy Redis
nomad job run jobs/services/redis.nomad.hcl

# Wait for Redis to be healthy
sleep 10

# Deploy Authelia
nomad job run jobs/services/authelia.nomad.hcl

# Wait for Authelia to start
sleep 15

# Check status
nomad job status authelia
curl https://authelia.lab.hartr.net/api/health
```

### 5. Test Login (1 minute)

```bash
# Open Authelia in browser
open https://authelia.lab.hartr.net

# Login with:
# Username: jack
# Password: <your password from step 2>
```

You should see the Authelia dashboard!

### 6. Deploy Protected Grafana (1 minute)

Grafana is already configured with Authelia protection:

```bash
nomad job run jobs/services/grafana.nomad.hcl
```

### 7. Test Protection (1 minute)

```bash
# Try to access Grafana
open https://grafana.lab.hartr.net

# Should redirect to Authelia login
# After logging in, you'll be redirected back to Grafana

# Run automated tests
./scripts/test-authelia-protection.fish
```

## What Happens Next

When you visit a protected service:

1. **First Visit** → Redirected to Authelia login
2. **Login** → Session created, stored in Redis
3. **Redirect** → Back to the service you wanted
4. **Session Persists** → All other protected services work without re-login
5. **Logout** → Logs you out of all services

## Protecting More Services

To protect any service, add **one line** to its Traefik tags:

```hcl
tags = [
  "traefik.enable=true",
  "traefik.http.routers.SERVICE.rule=Host(`service.lab.hartr.net`)",
  "traefik.http.routers.SERVICE.entrypoints=websecure",
  "traefik.http.routers.SERVICE.tls=true",
  "traefik.http.routers.SERVICE.tls.certresolver=letsencrypt",
  # ADD THIS LINE:
  "traefik.http.routers.SERVICE.middlewares=authelia@consulcatalog",
]
```

### Priority Order for Protection

**Phase 1 - Infrastructure** (protect these first):
```bash
# Already configured in access_control rules:
# - Grafana ✅ (job file updated)
# - Prometheus
# - Traefik Dashboard
```

**Phase 2 - Development Tools**:
- Jenkins
- Gitea
- Code Server
- Wiki

**Phase 3 - Personal Services**:
- Nextcloud
- Calibre
- Audiobookshelf
- FreshRSS

**Keep Public** (no protection):
- Homepage (main landing page)
- Whoami (test service)
- Docker Registry API (services need direct access)
- MinIO S3 API (service-to-service)

## Verification Checklist

After deployment, verify:

- [ ] Secrets stored in Vault: `vault kv get secret/authelia/config`
- [ ] Redis running: `nomad job status redis`
- [ ] Authelia running: `nomad job status authelia`
- [ ] Authelia healthy: `curl https://authelia.lab.hartr.net/api/health`
- [ ] Login page accessible: `open https://authelia.lab.hartr.net`
- [ ] Can login with your credentials
- [ ] Grafana redirects to Authelia
- [ ] After login, Grafana is accessible
- [ ] Session persists (visit Prometheus without re-login)

## Troubleshooting

### Login Loop (keeps redirecting)

```bash
# Check Redis is accessible
consul catalog service redis
redis-cli -h redis.service.consul PING

# Check Authelia logs
nomad alloc logs -f $(nomad job allocs authelia | grep running | awk '{print $1}' | head -1)
```

### 502 Bad Gateway

```bash
# Verify Authelia is registered
consul catalog service authelia

# Test Authelia endpoint
curl http://authelia.service.consul:9091/api/health
```

### "Access Denied" after login

```bash
# Check you're in the correct group
# User needs to be in a group that matches the access control rules
# Edit jobs/services/authelia.nomad.hcl users_database.yml section
```

### Service not protected

```bash
# Verify middleware tag is present
nomad job inspect SERVICE | grep authelia

# Check Traefik sees the middleware
curl http://traefik.lab.hartr.net/api/http/routers | jq '.[].middlewares'
```

## Advanced Configuration

### Add More Users

Edit `jobs/services/authelia.nomad.hcl`, add to users_database.yml:

```yaml
newuser:
  displayname: "New User"
  password: "$argon2id$YOUR_HASH"  # Generate with generate-authelia-password.fish
  email: newuser@lab.hartr.net
  groups:
    - users  # Or 'admins' for admin access
```

Then redeploy:
```bash
nomad job run jobs/services/authelia.nomad.hcl
```

### Enable 2FA

1. Login to Authelia
2. Click your username → Settings
3. Security → Register One-Time Password
4. Scan QR code with authenticator app
5. Enter verification code

Update access control for admin services:
```yaml
- domain:
    - vault.lab.hartr.net
    - nomad.lab.hartr.net
  policy: two_factor  # Changed from one_factor
```

### Setup Email Notifications

Edit `jobs/services/authelia.nomad.hcl`, uncomment SMTP section:

```yaml
notifier:
  smtp:
    host: smtp.gmail.com
    port: 587
    username: your-email@gmail.com
    password: your-app-password
    sender: Authelia <authelia@lab.hartr.net>
```

## Documentation

- **[AUTHELIA_QUICK_START.md](docs/AUTHELIA_QUICK_START.md)** - Overview and benefits
- **[AUTHELIA_SSO_SETUP.md](docs/AUTHELIA_SSO_SETUP.md)** - Complete configuration guide
- **[AUTHELIA_SSO_IMPLEMENTATION.md](docs/AUTHELIA_SSO_IMPLEMENTATION.md)** - Detailed implementation
- **[AUTHELIA_PROTECTION_EXAMPLES.md](docs/AUTHELIA_PROTECTION_EXAMPLES.md)** - Before/after examples

## Files Changed

### New Files
- `jobs/services/redis.nomad.hcl` - Redis for session storage
- `scripts/setup-authelia-secrets.fish` - Generate secrets
- `scripts/generate-authelia-password.fish` - Password hashing
- `scripts/deploy-authelia-sso.fish` - Automated deployment
- `scripts/test-authelia-protection.fish` - Test protection
- `docs/AUTHELIA_*.md` - Complete documentation

### Updated Files
- `jobs/services/authelia.nomad.hcl` - Vault integration, Redis, access control
- `jobs/services/grafana.nomad.hcl` - Added Authelia middleware

## Summary

You now have:
- ✅ Production-ready Authelia configuration
- ✅ Vault-backed secret storage
- ✅ Redis session persistence
- ✅ Complete access control rules
- ✅ Automated deployment scripts
- ✅ Testing tools
- ✅ Example protected service (Grafana)
- ✅ Comprehensive documentation

**Estimated deployment time**: 10-15 minutes

**Ready to deploy?** Start with step 1 above! 🚀
