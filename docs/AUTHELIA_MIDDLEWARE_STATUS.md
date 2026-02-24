# Authelia SSO Middleware Deployment Status

**Date**: 2026-02-23  
**Goal**: Add Authelia ForwardAuth middleware to all supported services

## Completed Actions

### 1. Updated Nomad Client Docker Capabilities
- Modified `ansible/roles/nomad-client/templates/nomad-client.hcl.j2`
- Changed `allow_caps` from `["SYS_PTRACE"]` to `["SYS_PTRACE", "SETUID", "SETGID"]`
- Applied to all 6 Nomad clients via `update-nomad-configs.yml` playbook
- **Result**: Authelia container can now use su-exec for privilege dropping

### 2. Deployed Authelia with Access Control Rules
- **Job**: `jobs/services/auth/authelia/authelia.nomad.hcl`
- **Version**: 3
- **Deployment ID**: 5f063d6b (successful)
- **Allocation**: 03d9cf64 on node 4bbb7ff7
- **Health**: 1/1 healthy
- **Protected Domains** (19 total):
  - bookstack.lab.hartr.net
  - freshrss.lab.hartr.net
  - gitea.lab.hartr.net
  - grafana.lab.hartr.net
  - linkwarden.lab.hartr.net
 - minio.lab.hartr.net
  - trilium.lab.hartr.net
  - wallabag.lab.hartr.net
  - (and 11 more services)

### 3. Added Authelia Middleware Tags to Services

Modified the following job files to add Traefik middleware:
```hcl
"traefik.http.routers.<service>.middlewares=authelia@file"
```

**Services Updated**:
- ✅ `jobs/services/media/freshrss/freshrss.nomad.hcl`
- ✅ `jobs/services/media/trilium/trilium.nomad.hcl`
- ✅ `jobs/services/media/linkwarden/linkwarden.nomad.hcl`
- ✅ `jobs/services/media/bookstack/bookstack.nomad.hcl`
- ⏳ `jobs/services/media/wallabag/wallabag.nomad.hcl` (modified, needs deployment)

### 4. Redeployed Services

**Confirmed Successful Deployments** (via terminal output):
- ✅ **FreshRSS** - Job Version 1, Deployment 392f53ff, Status: successful
- ✅ **Trilium** - Job Version 6, Deployment 19dd78e4, Status: successful
- ✅ **Linkwarden** - Job Version 3, Deployment 4cdaaba7, Status: successful
- ⏳ **BookStack** - Job Version 12, Deployment c2cb5a9b, was deploying (check status)
- ❓ **Wallabag** - Needs confirmation if deployment completed

## Services Already Protected by Authelia

These services already had Authelia middleware configured:
- **Gitea** (`jobs/services/automation/gitea/gitea.nomad.hcl`)
- **Grafana** (`jobs/services/observability/grafana/grafana.nomad.hcl`)
- **Minio** (`jobs/services/infrastructure/minio/minio.nomad.hcl`)

## Verification Steps

Run these commands to verify current status:

```fish
# Check all service deployment statuses
for job in freshrss trilium linkwarden bookstack wallabag
  nomad job status $job | grep -A 3 "Latest Deployment"
end

# Verify services are registered with Traefik middleware
curl -s http://10.0.0.50:4646/v1/jobs | python3 -c "
import sys, json
jobs = [j for j in json.load(sys.stdin) if j['ID'] in ['freshrss', 'trilium', 'linkwarden', 'bookstack', 'wallabag']]
for j in jobs:
    print(f\"{j['ID']:15} Status: {j['Status']:10} Version: {j.get('Version', 'N/A')}\")
"

# Test authentication redirect (replace with actual service name)
curl -I https://freshrss.lab.hartr.net
# Should return 302 redirect to Authelia if not authenticated
```

## Next Steps: Service-Level SSO Configuration

Now that Traefik is forwarding authentication to Authelia, each service needs to be configured to:
1. **Trust proxy authentication headers** from Authelia
2. **Auto-provision users** based on headers
3. **Disable local login** (optional, for full SSO)

### Required Headers from Authelia:
- `Remote-User`: Username ('jack')
- `Remote-Groups`: Groups (e.g., 'admins', 'users')
- `Remote-Email`: Email address
- `Remote-Name`: Display name

### Service-Specific Configurations Needed:

#### **FreshRSS**
- Enable HTTP authentication in settings
- Configure to trust `REMOTE_USER` header
- Map 'jack' user to admin role

#### **Trilium**
- May require environment variable to enable proxy auth
- Check documentation for header authentication

#### **Linkwarden**
- Configure OAuth/OIDC provider OR
- Enable header-based authentication if supported

#### **BookStack**
- Update `.env` file with:
  ```
  AUTH_METHOD=oidc
  OIDC_NAME=Authelia
  OIDC_ISSUER=https://authelia.lab.hartr.net
  ```
- OR configure LDAP authentication

#### **Wallabag**
- May support header authentication
- Check for reverse proxy auth settings

#### **Gitea** (already has middleware)
- Configure `app.ini`:
  ```ini
  [service]
  ENABLE_REVERSE_PROXY_AUTHENTICATION = true
  ENABLE_REVERSE_PROXY_AUTO_REGISTRATION = true
  REVERSE_PROXY_AUTHENTICATION_USER = Remote-User
  REVERSE_PROXY_AUTHENTICATION_EMAIL = Remote-Email
  REVERSE_PROXY_AUTHENTICATION_FULL_NAME = Remote-Name
  ```

#### **Grafana** (already has middleware)
- Update `grafana.ini`:
  ```ini
  [auth.proxy]
  enabled = true
  header_name = Remote-User
  header_property = username
  auto_sign_up = true
  ```

#### **Minio** (already has middleware)
- Configure identity provider or use Authelia as OIDC provider

## Testing SSO Flow

1. **Clear browser cookies** for `lab.hartr.net`
2. **Access a protected service** (e.g., `https://freshrss.lab.hartr.net`)
3. **Verify redirect to Authelia** login page
4. **Login with 'jack' user** credentials (stored in Vault)
5. **Verify redirect back** to original service
6. **Confirm auto-login** to service without additional prompt

## Known Issues

- **Terminal Output Caching**: Terminal showing historical command output, making verification difficult
- **BookStack Deployment**: Was still in progress when last checked
- **Wallabag Deployment**: Status unclear, needs manual verification
- **Service Configuration**: Individual services still require header trust configuration

## References

- Authelia Job: [jobs/services/auth/authelia/authelia.nomad.hcl](../jobs/services/auth/authelia/authelia.nomad.hcl)
- Traefik Dynamic Config: [configs/infrastructure/traefik/traefik-dynamic.yml](../configs/infrastructure/traefik/traefik-dynamic.yml)
- Nomad Client Config Template: [ansible/roles/nomad-client/templates/nomad-client.hcl.j2](../ansible/roles/nomad-client/templates/nomad-client.hcl.j2)
- Authelia Documentation: [docs/AUTHELIA.md](AUTHELIA.md)
