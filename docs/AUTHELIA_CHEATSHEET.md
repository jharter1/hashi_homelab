# Authelia SSO - Quick Command Reference

## Initial Setup

```bash
# 1. Generate secrets and store in Vault
./scripts/setup-authelia-secrets.fish

# 2. Generate password hash
./scripts/generate-authelia-password.fish

# 3. Update password hash in authelia.nomad.hcl
nano jobs/services/authelia.nomad.hcl
# Replace: password: "$argon2id$REPLACE_WITH_ACTUAL_HASH"

# 4. Deploy everything
./scripts/deploy-authelia-sso.fish
```

## Manual Deployment

```bash
# Deploy Redis
nomad job run jobs/services/redis.nomad.hcl

# Deploy Authelia
nomad job run jobs/services/authelia.nomad.hcl

# Deploy protected Grafana
nomad job run jobs/services/grafana.nomad.hcl
```

## Testing

```bash
# Test protection status
./scripts/test-authelia-protection.fish

# Check Authelia health
curl https://authelia.lab.hartr.net/api/health

# Test login
open https://authelia.lab.hartr.net
```

## Monitoring

```bash
# Check job status
nomad job status authelia
nomad job status redis

# View logs
nomad alloc logs -f $(nomad job allocs authelia | grep running | awk '{print $1}' | head -1)

# Check Consul registration
consul catalog service authelia
consul catalog service redis
```

## Protect a Service

```bash
# 1. Edit the service job file
nano jobs/services/SERVICE.nomad.hcl

# 2. Add middleware tag
tags = [
  # ... existing tags ...
  "traefik.http.routers.SERVICE.middlewares=authelia@consulcatalog",
]

# 3. Redeploy
nomad job run jobs/services/SERVICE.nomad.hcl

# 4. Test
curl -I https://SERVICE.lab.hartr.net
# Should return 302 redirect to Authelia
```

## User Management

```bash
# Generate new password hash
./scripts/generate-authelia-password.fish

# Add user to authelia.nomad.hcl
nano jobs/services/authelia.nomad.hcl
# Add to users_database.yml section

# Redeploy
nomad job run jobs/services/authelia.nomad.hcl
```

## Troubleshooting

```bash
# Login loop
redis-cli -h redis.service.consul PING
nomad alloc logs -f $(nomad job allocs authelia | grep running | awk '{print $1}' | head -1) | grep session

# 502 errors
consul catalog service authelia
curl http://authelia.service.consul:9091/api/health

# Access denied
nomad alloc logs -f $(nomad job allocs authelia | grep running | awk '{print $1}' | head -1) | grep "access control"

# Service not protected
nomad job inspect SERVICE | grep middleware

# API endpoints getting 401 errors
# Add bypass rules for /api/*, /opds/*, etc in access_control.rules
# Example:
# - domain: calibre.lab.hartr.net
#   resources: ["^/opds.*$"]
#   policy: bypass
```

## Useful Vault Commands

```bash
# View stored secrets
vault kv get secret/authelia/config

# Update a secret
vault kv put secret/authelia/config jwt_secret="new-value"

# Delete secrets (CAUTION!)
vault kv delete secret/authelia/config
```

## URLs

- **Authelia**: https://authelia.lab.hartr.net
- **Grafana** (protected): https://grafana.lab.hartr.net
- **Prometheus** (to be protected): https://prometheus.lab.hartr.net

## Default Credentials

- **Username**: jack
- **Password**: (set during password hash generation)
- **Groups**: admins, users

## Protection Pattern

```hcl
# Standard protection (add to any service)
"traefik.http.routers.NAME.middlewares=authelia@consulcatalog"
```

## Access Control Summary

| Domain | Policy | Groups | Status |
|--------|--------|--------|--------|
| authelia.lab.hartr.net | bypass | all | Always accessible |
| home.lab.hartr.net | bypass | all | Public |
| whoami.lab.hartr.net | bypass | all | Public |
| grafana.lab.hartr.net | one_factor | users, admins | ✅ Protected |
| prometheus.lab.hartr.net | one_factor | users, admins | ⏭️ Ready |
| vault.lab.hartr.net | one_factor | admins | ⏭️ Ready |
| nomad.lab.hartr.net | one_factor | admins | ⏭️ Ready |
| consul.lab.hartr.net | one_factor | admins | ⏭️ Ready |

## Files

- Job: `jobs/services/authelia.nomad.hcl`
- Redis: `jobs/services/redis.nomad.hcl`
- Scripts: `scripts/setup-authelia-secrets.fish`, `scripts/generate-authelia-password.fish`, `scripts/deploy-authelia-sso.fish`, `scripts/test-authelia-protection.fish`
- Docs: `docs/AUTHELIA.md`
