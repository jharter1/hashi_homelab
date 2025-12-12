# Vault PKI Certificate Issuance via Nomad Templates - Investigation

## Date
December 11, 2025

## Environment
- **Nomad Version**: v1.11.0 (BuildDate 2025-11-11T16:18:19Z)
- **Vault Version**: HA cluster, 3 nodes (10.0.0.30-32)
- **Root Token**: [REDACTED - stored securely]
- **Cluster**: 3 servers (10.0.0.50-52), 3 clients (10.0.0.60-62)

## What Works ✅

### 1. Vault PKI Infrastructure
- **Root CA**: `pki/` (10 year TTL) - fully functional
- **Intermediate CA**: `pki_int/` (5 year TTL) - fully functional
- **PKI Issuer**: 9ef56000-3e99-7c66-bf51-1dfb35f186f0 with `issuer_name="intermediate-ca"`
- **PKI Role**: `service` role configured correctly:
  ```bash
  vault write pki_int/roles/service \
    issuer_ref="intermediate-ca" \
    allowed_domains="home,homelab.local" \
    allow_subdomains=true \
    ttl=720h \
    max_ttl=720h
  ```

### 2. Vault JWT Authentication
- **Backend**: `jwt-nomad` configured and operational
- **Role**: `nomad-workloads` with:
  - `bound_audiences=["vault.io"]`
  - `token_policies=["nomad-workloads"]`
  - `token_period=30m`
- **Policy**: `nomad-workloads` includes:
  ```hcl
  path "secret/data/nomad/*" {
    capabilities = ["read", "list"]
  }
  
  path "pki_int/issue/service" {
    capabilities = ["create", "update"]
  }
  ```

### 3. Manual Token & PKI Testing
**All manual testing succeeds:**

```bash
# 1. Server token can create child tokens
vault token create -policy=nomad-workloads
# ✅ SUCCESS

# 2. Child token can issue certificates
vault write pki_int/issue/service common_name=test.home ttl=1h
# ✅ SUCCESS - Certificate issued (CN=test.home)

# 3. Workload identity tokens can issue certificates
# Extracted token from allocation: [REDACTED - example workload token]
vault write pki_int/issue/service common_name=test.home ttl=1h
# ✅ SUCCESS - Certificate issued
```

### 4. Nomad Workload Identity
- **vault_hook IS RUNNING** (after minimal config reset)
- **vault_token file created** in `/opt/nomad/alloc/<ID>/<task>/secrets/vault_token`
- **JWT file created**: `nomad_vault_default.jwt` in secrets directory
- **Token metadata correct**:
  ```
  display_name: jwt-nomad-traefik
  policies: [default nomad-workloads]
  meta: {nomad_job_id:traefik, nomad_namespace:default, nomad_task:traefik, role:nomad-workloads}
  ```

### 5. Nomad Templates - READ Operations
**Simple KV secret reads work perfectly:**

```hcl
template {
  data = "{{ with secret \"secret/data/nomad/test\" }}{{ .Data.data.foo }}{{ end }}"
  destination = "local/test.txt"
}
# ✅ SUCCESS - Template rendered "bar" from Vault secret
```

Test job `vault-hook-test` deployed successfully and rendered KV secrets.

## What Doesn't Work ❌

### 1. Nomad Templates - WRITE Operations (PKI)
**PKI certificate issuance via templates fails:**

```hcl
template {
  data = <<EOH
{{ with secret "pki_int/issue/service" "common_name=*.home" "alt_names=home" "ttl=720h" }}
{{ .Data.certificate }}{{ end }}
EOH
  destination = "local/tls.crt"
}
```

**Error**: `Missing: vault.write(pki_int/issue/service -> b5ad0961)`

- `b5ad0961` is Consul Template's internal query ID, NOT a Vault token
- Error persists across all allocation attempts
- Same error with different template syntaxes

### 2. Template Syntax Variations Attempted
All failed with the same `b5ad0961` error:

**Attempt 1**: Standard `secret` function
```hcl
{{ with secret "pki_int/issue/service" "common_name=*.home" "alt_names=home" "ttl=720h" }}
{{ .Data.certificate }}{{ end }}
```

**Attempt 2**: Using `pkiCert` function
```hcl
{{ with pkiCert "pki_int/issue/service" "common_name=*.home" "alt_names=home" "ttl=720h" }}
{{ .Cert }}{{ end }}
```
Error changed to: `Missing: vault.pki(pki_int/issue/service->/opt/nomad/alloc/.../local/tls.crt)`

**Attempt 3**: Added `VAULT_ADDR` environment variable
```hcl
env {
  VAULT_ADDR = "http://10.0.0.30:8200"
}
```
No change - same error

### 3. Observed Behavior
- Nomad client logs show: `[WARN] agent: (view) vault.write(pki_int/issue/service -> b5ad0961): Error making API request.`
- No actual HTTP requests reach Vault (verified via Vault server logs)
- vault_token file exists and is valid
- Token manually works for PKI issuance
- Consul Template appears unable to use the token for write operations

## Minimal Nomad Configuration (Current)

### Server Config
```hcl
datacenter = "dc1"
data_dir = "/opt/nomad"

server {
  enabled          = true
  bootstrap_expect = 3
}

vault {
  enabled = true
  address = "http://10.0.0.30:8200"
  token = "{{ vault_token }}"
  
  default_identity {
    aud  = ["vault.io"]
    file = true
    ttl  = "1h"
  }
  
  jwt_auth_backend_path = "jwt-nomad"
}
```

### Client Config
```hcl
datacenter = "dc1"
data_dir = "/opt/nomad"

client {
  enabled = true
  servers = ["10.0.0.50:4647", "10.0.0.51:4647", "10.0.0.52:4647"]
}

vault {
  enabled               = true
  address               = "http://10.0.0.30:8200"
  jwt_auth_backend_path = "jwt-nomad"
}
```

## Dead Ends 🚫

### 1. Configuration Changes That Didn't Help
- ✗ Adding `file=true` to client config (causes error per HashiCorp docs)
- ✗ Removing `default_identity` from client (per best practices, but no change)
- ✗ Adding `jwt_auth_backend_path` to server and client
- ✗ Regenerating Nomad server tokens with `nomad-workloads` policy
- ✗ Setting PKI issuer name manually
- ✗ Restarting servers (3x) and clients (2x)
- ✗ Purging and redeploying job (6-7x)
- ✗ Complete Nomad data wipe and minimal config redeploy
- ✗ Adding `VAULT_ADDR` environment variable to task
- ✗ Using `pkiCert` function instead of `secret`
- ✗ Trying different template syntaxes

### 2. Troubleshooting Attempts
- ✗ Checked Vault server logs - no requests arriving
- ✗ Verified token permissions - token works manually
- ✗ Checked vault_token file - exists and is valid
- ✗ Verified vault_hook is running - confirmed via file creation
- ✗ Searched Nomad logs for vault_hook errors - no errors found
- ✗ Checked Consul Template logs - only shows "Error making API request"

## Theories & Possibilities 🤔

### 1. Consul Template Version/Compatibility Issue
**Theory**: The embedded Consul Template in Nomad 1.11.0 may not support Vault write operations via workload identity tokens.

**Evidence**:
- READ operations work perfectly
- WRITE operations fail silently
- No actual HTTP requests to Vault
- Manual testing with same token succeeds

**Next Steps**:
- Check Nomad 1.11.0 release notes for Consul Template version
- Search for known issues with `vault.write()` in Nomad templates
- Test with newer/older Nomad version

### 2. Missing Template Configuration
**Theory**: Templates may need explicit configuration to use the vault_token file for write operations.

**Evidence**:
- vault_token file exists but may not be referenced
- Consul Template might default to different auth method
- No explicit vault configuration in template stanza

**Next Steps**:
- Research `template` stanza vault configuration options
- Check if there's a `vault_token` or `vault_token_file` parameter
- Look for template-level Vault auth configuration

### 3. Vault Policy Permission Issue
**Theory**: Despite manual testing working, there might be a subtle permission difference when accessed via Consul Template.

**Evidence**:
- Token has correct policies when inspected
- Manual vault CLI commands work
- Template operations fail

**Next Steps**:
- Enable Vault audit logging
- Capture exact API requests (if any) from Consul Template
- Compare manual request vs template request

### 4. Nomad Workload Identity Bug
**Theory**: There's a bug in Nomad 1.11.0's workload identity integration with Vault write operations.

**Evidence**:
- Everything configured per HashiCorp best practices
- Manual testing proves infrastructure correct
- Only template-based writes fail
- Recent Nomad version (Nov 2025 build)

**Next Steps**:
- Search Nomad GitHub issues for similar reports
- Check Nomad 1.11.x changelog for related fixes
- Consider filing bug report with reproduction steps

### 5. Three Separate Templates Issue
**Theory**: Multiple templates trying to write to the same PKI endpoint causes conflicts.

**Evidence**:
- Three separate templates each calling `pki_int/issue/service`
- Each call would create a different certificate
- Possible race condition or caching issue

**Next Steps**:
- Consolidate into single template that writes all three files
- Use `pkiCert` with caching (if supported)
- Research proper pattern for multi-file PKI certificates in Nomad

## Relevant Documentation 📚

### HashiCorp Official Docs
1. **Nomad Vault Integration**: https://developer.hashicorp.com/nomad/docs/integrations/vault-integration
2. **Nomad Workload Identity**: https://developer.hashicorp.com/nomad/docs/concepts/workload-identity
3. **Nomad Template Stanza**: https://developer.hashicorp.com/nomad/docs/job-specification/template
4. **Vault PKI Secrets Engine**: https://developer.hashicorp.com/vault/docs/secrets/pki
5. **Consul Template Vault Integration**: https://github.com/hashicorp/consul-template#vault

### Consul Template Functions
1. **secret function**: https://github.com/hashicorp/consul-template/blob/main/docs/templating-language.md#secret
2. **pkiCert function**: https://github.com/hashicorp/consul-template/blob/main/docs/templating-language.md#pkicert

### GitHub Issues to Research
- Search: "nomad vault template write pki"
- Search: "nomad workload identity vault write"
- Search: "consul template vault.write missing"
- Search: "nomad 1.11 vault pki"

## Configuration Files

### Current Traefik Job (Failing)
Location: `/Users/jackharter/Developer/hashi_homelab/jobs/system/traefik.nomad.hcl`

```hcl
vault {}

env {
  VAULT_ADDR = "http://10.0.0.30:8200"
}

template {
  data = <<EOH
{{ with secret "pki_int/issue/service" "common_name=*.home" "alt_names=home" "ttl=720h" }}
{{ .Data.certificate }}{{ end }}
EOH
  destination = "local/tls.crt"
  change_mode = "noop"
}

template {
  data = <<EOH
{{ with secret "pki_int/issue/service" "common_name=*.home" "alt_names=home" "ttl=720h" }}
{{ .Data.private_key }}{{ end }}
EOH
  destination = "local/tls.key"
  change_mode = "noop"
}

template {
  data = <<EOH
{{ with secret "pki_int/issue/service" "common_name=*.home" "alt_names=home" "ttl=720h" }}
{{ .Data.issuing_ca }}{{ end }}
EOH
  destination = "local/ca.crt"
  change_mode = "noop"
}
```

### Test Job (Working - KV Read)
Location: `/Users/jackharter/Developer/hashi_homelab/jobs/test/vault-hook-test.nomad.hcl`

```hcl
vault {}

template {
  data = "{{ with secret \"secret/data/nomad/test\" }}{{ .Data.data.foo }}{{ end }}"
  destination = "local/test.txt"
}
```
Status: ✅ Deployment successful, template rendered correctly

## Key Diagnostic Commands

### Check allocation status
```bash
nomad job status traefik
nomad alloc status <alloc-id>
```

### Verify vault_token file
```bash
ssh ubuntu@10.0.0.6X "sudo cat /opt/nomad/alloc/<alloc-id>/<task>/secrets/vault_token"
```

### Test token manually
```bash
set -x VAULT_ADDR http://10.0.0.30:8200
set -x VAULT_TOKEN <token-from-file>
vault write pki_int/issue/service common_name=test.home ttl=1h
```

### Check Nomad client logs
```bash
ssh ubuntu@10.0.0.6X "sudo journalctl -u nomad --since '5 minutes ago' | grep -i vault"
```

### Check Vault server logs
```bash
ssh ubuntu@10.0.0.30 "sudo journalctl -u vault --since '5 minutes ago'"
```

## Next Session Action Items

1. **Research Consul Template version** in Nomad 1.11.0 - check if `vault.write()` is supported
2. **Search GitHub issues** for similar problems with Nomad + Vault + PKI
3. **Try alternative approach**: Use a single template or external script to issue cert
4. **Enable Vault audit logging** to see if any requests arrive from Consul Template
5. **Test with different Nomad version** (1.10.x or 1.12.x if available)
6. **Consider workaround**: Init container that issues cert via vault CLI, writes to shared volume
7. **File bug report** if all else fails - we have complete reproduction steps

## Success Criteria
- Traefik allocations can successfully render PKI certificates via Nomad templates
- Certificates automatically renew before expiration
- Solution follows HashiCorp best practices for workload identity
- No manual intervention required after initial setup

## Workaround Options (If Templates Don't Work)

### Option 1: Vault Agent Sidecar
Deploy Vault Agent as sidecar container to handle cert issuance:
```hcl
task "vault-agent" {
  driver = "docker"
  lifecycle {
    hook = "prestart"
    sidecar = true
  }
  # Configure vault agent to issue and renew certs
}
```

### Option 2: Init Script
Use prestart task to issue cert via vault CLI:
```hcl
task "issue-cert" {
  driver = "raw_exec"
  lifecycle {
    hook = "prestart"
  }
  # Script that uses vault CLI to issue cert
}
```

### Option 3: External Cert Management
Use cert-manager or similar tool outside Nomad to manage certificates, mount as files.

### Option 4: Traefik ACME/Let's Encrypt
Use Traefik's built-in ACME support instead of Vault PKI (requires public domain).
