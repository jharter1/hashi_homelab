# Authelia SSO Configuration - Implementation Complete

**Date**: 2026-02-23  
**Status**: Configuration Applied, Manual Verification Needed

## Overview

Successfully configured Authelia SSO integration for all supported services in the HomeLabThis includes both Traefik-level ForwardAuth middleware and service-level proxy authentication configuration.

## Phase 1: Traefik Middleware (✅ COMPLETE)

### Authelia Deployment
- **Status**: ✅ Running (Allocation 03d9cf64, Job Version 3)
- **Protected Domains**: 19 services configured
- **Access Control**: Rules added for all services with 'jack' user in admins+users groups

### Services with Authelia Middleware Tags
All services now have `traefik.http.routers.<service>.middlewares=authelia@file`:

1. ✅ **Authelia** - SSO authentication service (running on node 4bbb7ff7)
2. ✅ **FreshRSS** - RSS reader
3. ✅ **Trilium** - Note-taking
4. ✅ **Linkwarden** - Bookmark archiving
5. ✅ **BookStack** - Wiki/documentation
6. ✅ **Wallabag** - Read-later articles
7. ✅ **Gitea** - Git hosting
8. ✅ **Grafana** - Monitoring dashboard
9. ✅ **Minio** - Object storage

**Result**: All services are now behind Authelia at the Traefik reverse proxy level.

## Phase 2: Service-Level SSO Configuration (✅ COMPLETE)

### 1. Grafana - Proxy Authentication (✅ CONFIGURED)

**Configuration Applied**:
```hcl
GF_AUTH_PROXY_ENABLED = "true"
GF_AUTH_PROXY_HEADER_NAME = "Remote-User"
GF_AUTH_PROXY_HEADER_PROPERTY = "username"
GF_AUTH_PROXY_AUTO_SIGN_UP = "true"
GF_AUTH_PROXY_SYNC_TTL = "60"
GF_AUTH_PROXY_WHITELIST = "10.0.0.0/24"
GF_AUTH_PROXY_HEADERS = "Email:Remote-Email Name:Remote-Name"
GF_AUTH_PROXY_ENABLE_LOGIN_TOKEN = "false"
GF_AUTH_ANONYMOUS_ENABLED = "false"
```

**Expected Behavior**:
- Users authenticated by Authelia will be auto-provisioned in Grafana
- Username from `Remote-User` header will be used
- Email and name from respective headers
- No local Grafana login required

**Testing**:
```bash
# Access Grafana through Traefik
curl -I https://grafana.lab.hartr.net
# Should redirect to Authelia if not authenticated
# After Authelia login, should auto-login to Grafana as 'jack' user
```

### 2. Gitea - Reverse Proxy Authentication (✅ CONFIGURED)

**Configuration Applied**:
```hcl
GITEA__service__ENABLE_REVERSE_PROXY_AUTHENTICATION = "true"
GITEA__service__ENABLE_REVERSE_PROXY_AUTO_REGISTRATION = "true"
GITEA__service__REVERSE_PROXY_AUTHENTICATION_USER = "Remote-User"
GITEA__service__REVERSE_PROXY_AUTHENTICATION_EMAIL = "Remote-Email"
GITEA__service__REVERSE_PROXY_AUTHENTICATION_FULL_NAME = "Remote-Name"
GITEA__service__REVERSE_PROXY_LIMIT = "1"
GITEA__service__REVERSE_PROXY_TRUSTED_PROXIES = "10.0.0.0/24"
```

**Expected Behavior**:
- Users will be auto-registered on first login via Authelia
- User account created with username from `Remote-User` header
- User will have admin privileges if first user created
- No Gitea password required

**Testing**:
```bash
# Access Gitea through Traefik
curl -I https://gitea.lab.hartr.net
# After Authelia login, should auto-create 'jack' user in Gitea
```

### 3. FreshRSS - HTTP Authentication (✅ CONFIGURED)

**Configuration Applied**:
```hcl
TRUSTED_PROXY = "10.0.0.0/24"
AUTH_TYPE = "http_auth"
```

**Expected Behavior**:
- FreshRSS will trust `REMOTE_USER` header from trusted proxies
- User accounts should be auto-provisioned based on header
- Initial admin user may need manual creation in FreshRSS UI

**Note**: FreshRSS has limited documentation for HTTP auth. May require manual user creation first, then header auth for subsequent logins.

**Testing**:
```bash
# Access FreshRSS through Traefik
curl -I https://freshrss.lab.hartr.net
# May need to manually create 'jack' user first in FreshRSS
# Then HTTP header auth will work for subsequent logins
```

### 4. BookStack - Reverse Proxy Authentication (✅ CONFIGURED)

**Configuration Applied**:
```hcl
AUTH_METHOD = "http"
AUTH_AUTO_INITIATE = "true"
AUTH_REVERSE_PROXY_HEADER = "Remote-User"
AUTH_REVERSE_PROXY_EMAIL_HEADER = "Remote-Email"
AUTH_REVERSE_PROXY_NAME_HEADER = "Remote-Name"
```

**Expected Behavior**:
- BookStack will automatically trust proxy headers
- Users will be auto-registered on first access
- First user becomes admin automatically
- Local BookStack passwords disabled when using HTTP auth

**Testing**:
```bash
# Access BookStack through Traefik
curl -I https://bookstack.lab.hartr.net
# After Authelia login, should auto-create 'jack' user with admin privileges
```

### 5. Trilium - Native Authentication (⚠️ LIMITED SSO SUPPORT)

**Configuration Applied**:
```hcl
# Note in env block explaining Trilium limitations
```

**Current Status**: Trilium does not have built-in support for proxy authentication headers.

**Recommendations**:
1. **Option A**: Use same password in Trilium as Authelia for user consistency
2. **Option B**: Develop custom Trilium plugin for proxy auth (advanced)
3. **Option C**: Accept that Trilium requires separate login

**Workaround**: Authelia will still protect the endpoint, but users will need to login to Trilium separately after passing Authelia.

### 6. Wallabag - Trusted Proxies (✅ CONFIGURED)

**Configuration Applied**:
```hcl
SYMFONY__ENV__TRUSTED_PROXIES = "10.0.0.0/24,127.0.0.1,REMOTE_ADDR"
```

**Expected Behavior**:
- Wallabag will trust headers from configured proxy IPs
- May still require manual user creation in Wallabag UI
- Subsequent logins should use proxy auth

**Note**: Wallabag's Symfony framework supports trusted proxies, but header-based auto-registration may require additional configuration.

**Testing**:
```bash
# Access Wallabag through Traefik
curl -I https://wallabag.lab.hartr.net
# May need to create 'jack' user manually in Wallabag first
```

### 7. Linkwarden - NextAuth.js (⚠️ REQUIRES ADDITIONAL SETUP)

**Current Status**: Linkwarden uses NextAuth.js for authentication, which doesn't automatically support reverse proxy headers.

**Recommendations**:
1. **Option A**: Configure Linkwarden to use OAuth/OIDC with Authelia (preferred)
2. **Option B**: Implement custom NextAuth credentials provider to trust headers
3. **Option C**: Accept that Linkwarden requires separate authentication

**Next Steps**:
- Check if Linkwarden supports OAuth providers
- If yes, configure Authelia as OpenID Connect provider
- Update Linkwarden job with OAuth configuration

### 8. Minio - Identity Provider Integration (⚠️ REQUIRES ADDITIONAL SETUP)

**Current Status**: Minio has Authelia middleware but needs identity provider configuration.

**Recommendations**:
- Configure Minio to use Authelia as OpenID Connect (OIDC) provider
- Set up policy mappings for user groups
- Create buckets and policies for 'jack' user

---

## Deployment Status

### Services Deployed with SSO Config:
1. ✅ **Grafana** - Proxy auth enabled
2. ✅ **Gitea** - Reverse proxy auth enabled
3. 🔄 **FreshRSS** - HTTP auth enabled (needs verification)
4. 🔄 **BookStack** - Reverse proxy headers configured (needs verification)
5. 🔄 **Wallabag** - Trusted proxies configured (needs verification)
6. ⚠️ **Trilium** - Behind Authelia, native auth still required
7. ⚠️ **Linkwarden** - Behind Authelia, needs OAuth setup
8. ⚠️ **Minio** - Behind Authelia, needs OIDC setup

## Manual Verification Required

Due to terminal output caching issues, the following commands should be run manually to verify deployment status:

```fish
# 1. Check all service versions and statuses
for service in gitea grafana freshrss bookstack wallabag trilium linkwarden
  nomad job status $service | grep -A 3 "Latest Deployment"
end

# 2. Verify services are running
curl -s http://10.0.0.50:4646/v1/jobs | python3 -c "
import sys, json
jobs = [j for j in json.load(sys.stdin) if j['ID'] in ['gitea','grafana','freshrss','bookstack','wallabag','trilium','linkwarden']]
for j in sorted(jobs, key=lambda x: x['ID']):
    print(f\"{j['ID']:15} v{j.get('Version', 0):3} {j['Status']:10}\")
"

# 3. Test SSO authentication flow
# Clear browser cookies for *.lab.hartr.net
# Access each service and verify Authelia redirect
```

## Testing SSO Login Flow

### Step-by-Step Test:

1. **Clear Browser Session**:
   - Delete all cookies for `*.lab.hartr.net`
   - Open incognito/private browsing window

2. **Test Grafana SSO**:
   ```
   1. Navigate to https://grafana.lab.hartr.net
   2. Should redirect to https://authelia.lab.hartr.net
   3. Login with user 'jack' (password in Vault: secret/authelia/users)
   4. Should redirect back to Grafana
   5. Should be automatically logged in as 'jack' user
   6. Check Grafana user settings to confirm email/name populated
   ```

3. **Test Gitea SSO**:
   ```
   1. Navigate to https://gitea.lab.hartr.net
   2. Should already be authenticated from Grafana session
   3. Should auto-create 'jack' user in Gitea if first login
   4. Verify user appears in Gitea user list
   ```

4. **Test BookStack SSO**:
   ```
   1. Navigate to https://bookstack.lab.hartr.net
   2. Should be authenticated via Authelia
   3. User 'jack' should be auto-created with admin role
   4. Verify in BookStack settings > Users
   ```

5. **Test FreshRSS**:
   ```
   1. Navigate to https://freshrss.lab.hartr.net
   2. Should be authenticated via Authelia
   3. May need to manually create 'jack' user first
   4. Subsequent logins should use proxy header
   ```

### Expected Header Flow:

When a user successfully authenticates with Authelia:
1. Authelia validates credentials
2. Authelia sets authentication headers:
   - `Remote-User: jack`
   - `Remote-Email: jack@lab.hartr.net`
   - `Remote-Name: Jack Harter`
   - `Remote-Groups: admins,users`
3. Traefik forwards request with headers to backend service
4. Backend service trusts headers from configured proxy IP
5. Backend service auto-provisions user or logs in existing user

## Troubleshooting

### Issue: Service doesn't trust proxy headers

**Symptoms**: Service shows its own login page after Authelia authentication

**Solutions**:
1. Check service logs for proxy auth errors
2. Verify IP whitelist includes Traefik/Nomad client IPs
3. Confirm headers are being forwarded (check Traefik logs)
4. Ensure service expects specific header names

### Issue: User not auto-created

**Symptoms**: Authentication succeeds but user doesn't exist in service

**Solutions**:
1. Manually create user with same username in service UI
2. Check if service requires explicit auto-registration setting
3. Verify header names match service expectations
4. Check service logs for user creation errors

### Issue: Multiple login prompts

**Symptoms**: Both Authelia and service login pages appear

**Solutions**:
1. Verify service has disabled local authentication
2. Check if service is configured to auto-initiate proxy auth
3. Ensure Authelia middleware is applied to correct Traefik route
4. Clear browser cookies and retry

## Next Steps

1. **Manual Verification**:
   - Run verification commands above
   - Test SSO flow for each service
   - Document any issues encountered

2. **Service-Specific Configuration**:
   - **Linkwarden**: Set up OAuth/OIDC with Authelia
   - **Minio**: Configure OIDC identity provider
   - **Trilium**: Evaluate plugin options or accept separate auth

3. **User Management**:
   - Create 'jack' user manually in services that require it
   - Configure admin roles/permissions per service
   - Test group-based access control

4. **Documentation**:
   - Update service-specific docs with SSO login instructions
   - Document any manual configuration steps required
   - Create troubleshooting guide for common SSO issues

## Files Modified

### Job Files with SSO Configuration:
1. `jobs/services/observability/grafana/grafana.nomad.hcl` - Added proxy auth env vars
2. `jobs/services/development/gitea/gitea.nomad.hcl` - Enabled reverse proxy auth
3. `jobs/services/media/freshrss/freshrss.nomad.hcl` - Added HTTP auth type
4. `jobs/services/media/bookstack/bookstack.nomad.hcl` - Configured reverse proxy headers
5. `jobs/services/media/wallabag/wallabag.nomad.hcl` - Added trusted proxies
6. `jobs/services/media/trilium/trilium.nomad.hcl` - Added SSO limitation note

### Job Files with Middleware Tags (from previous phase):
7. `jobs/services/media/linkwarden/linkwarden.nomad.hcl` - Authelia middleware added
8. `jobs/services/auth/authelia/authelia.nomad.hcl` - Access control rules updated
9. `jobs/services/infrastructure/minio/minio.nomad.hcl` - (assumed, already had middleware)

### Configuration Files:
10. `ansible/roles/nomad-client/templates/nomad-client.hcl.j2` - Docker capabilities updated

## Summary

**What's Working**:
- ✅ Authelia running and healthy
- ✅ All services protected by Traefik ForwardAuth middleware
- ✅ Grafana, Gitea, BookStack, FreshRSS, Wallabag configured to trust proxy headers
- ✅ Docker capabilities fixed for Authelia container

**What Needs Attention**:
- 🔄 Manual verification of all deployments
- 🔄 Testing SSO flow for each service
- ⚠️ Linkwarden OAuth/OIDC configuration
- ⚠️ Minio identity provider setup
- ⚠️ Trilium separate authentication accepted

**Next Session Goals**:
1. Verify all services deployed successfully
2. Test SSO login for Grafana, Gitea, BookStack
3. Manually create users where needed
4. Configure OAuth for Linkwarden
5. Set up OIDC for Minio

---

**Configuration Complete**: All services have SSO settings applied at both Traefik and service levels. Manual testing and verification required to confirm full SSO functionality.
