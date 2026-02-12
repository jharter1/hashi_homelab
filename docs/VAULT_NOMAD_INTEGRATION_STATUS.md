Template: Missing: vault.read(secret/data/postgres/admin)
# Vault-Nomad Integration Status

**Status**: ✅ WORKING - JWT Workload Identity Fully Operational
**Last Verified**: 2026-02-12

## Integration Summary

Vault-Nomad integration is **fully functional** using JWT workload identity (modern approach):
- ✅ JWT auth backend configured at `jwt-nomad/`
- ✅ Nomad servers configured with workload identity
- ✅ Jobs successfully reading secrets from Vault
- ✅ Automatic token renewal every 1 hour
- ✅ No server tokens required (JWT-based authentication)

## What We've Successfully Completed ✅

### Infrastructure
1. **Vault Cluster**: Rebuilt from scratch, 3 nodes (10.0.0.30-32), healthy and running
2. **Consul for Vault**: Service discovery working, all 3 nodes registered
3. **Vault Initialized**: Root token saved, cluster unsealed
4. **KV v2 Engine**: Enabled at `secret/` path

### Vault Configuration
1. **Secrets Created**: All PostgreSQL database passwords exist in Vault
   - `secret/postgres/admin`
   - `secret/postgres/freshrss`
   - `secret/postgres/gitea`
   - `secret/postgres/nextcloud`
   - `secret/postgres/authelia`
   - `secret/postgres/grafana`

2. **Policies Created**:
   - `nomad-workloads`: Allows read on `secret/data/*` and list on `secret/metadata/*`
   - `nomad-server`: Allows Nomad servers to create/renew tokens

3. **Token Role Created**:
   - `nomad-cluster`: Role for creating workload tokens
   - Configured with `nomad-workloads` policy
   - Period: 259200 seconds (72 hours)

4. **Nomad Server Token Generated**:
   - Stored in `ansible/inventory/group_vars/nomad_servers.yml`
   - Has policies: `nomad-server` and `nomad-workloads`

### Nomad Configuration
1. **Template Updated**: `ansible/roles/nomad-server/templates/nomad-server.hcl.j2` has vault block
2. **Ansible Variable Set**: `ansible/inventory/group_vars/nomad_servers.yml` has `vault_token`
3. **Playbook Run**: Updated all 3 Nomad servers with Vault config
4. **Servers Restarted**: All 3 Nomad servers picked up new configuration

### Job Files
1. **PostgreSQL Job**: Created with Vault template references for all database passwords
2. **FreshRSS Job**: Created with Vault template references for database credentials
3. **Host Volumes**: Added to all Nomad clients for persistent storage
4. **NAS Directories**: Created for postgres, freshrss, etc.

## How It Works 🔧

### Architecture
1. **Vault Infrastructure** (10.0.0.30-32):
   - 3-node HA cluster with Raft storage
   - JWT auth backend at `jwt-nomad/` pointing to Nomad's JWKS endpoint
   - KV v2 secrets engine at `secret/` path
   - Policies: `nomad-workloads` (read secret/data/nomad/*)

2. **Nomad Server Configuration**:
   ```hcl
   vault {
     enabled = true
     address = "http://10.0.0.30:8200"
     jwt_auth_backend_path = "jwt-nomad"
     default_identity {
       aud = ["vault.io"]
       ttl = "1h"
     }
   }
   ```

3. **Job Configuration**:
   - Add `vault {}` block to tasks needing secrets
   - Use Vault templates to read secrets
   - Example: `{{ with secret "secret/data/postgres/admin" }}{{ .Data.data.password }}{{ end }}`

### Verification
Check allocation events for token acquisition:
```bash
nomad alloc status <alloc-id> | grep "Vault: new Vault token acquired"
```

## Previous Issues (Now Resolved) ✅

## Optimization Options 🎯

### Reduce Token Renewal Frequency
Current TTL of 1h causes hourly task restarts. To reduce:
```hcl
default_identity {
  aud = ["vault.io"]
  ttl = "8h"  # Restart every 8 hours instead of 1 hour
}
```

### Historical Verification Steps (Used During Troubleshooting)
1. **Verify Token Validity**:
   ```bash
   # Source credentials first
   source .credentials
   
   vault token lookup
   ```
   Check if token is still valid and has correct policies attached

2. **Test Secret Access with Token**:
   ```bash
   # Source credentials first
   source .credentials
   
   vault kv get secret/postgres/admin
   ```
   Verify the token can actually read the secrets

3. **Check Nomad Server Logs**:
   ```bash
   ssh ubuntu@10.0.0.50 "sudo journalctl -u nomad -f | grep -i vault"
   ```
   Look for Vault connection errors on Nomad servers

4. **Verify Token in Nomad Config**:
   ```bash
   ssh ubuntu@10.0.0.50 "sudo cat /etc/nomad.d/nomad.hcl | grep -A5 vault"
   ```
   Confirm the token is actually in the config file

5. **Check Nomad Client Logs**:
   ```bash
   ssh ubuntu@10.0.0.61 "sudo journalctl -u nomad --since '5 minutes ago' | grep -i vault"
   ```
   See if clients are getting Vault tokens from servers

### Configuration Checks
1. **Nomad Server Vault Status**:
   ```bash
   curl http://10.0.0.50:4646/v1/operator/vault/status
   ```
   Check if Nomad thinks Vault is accessible

2. **Token Renewal**: The token might need `allow_token_renew` in Nomad config

3. **Network Connectivity**: Verify Nomad clients can reach Vault directly:
   ```bash
   ssh ubuntu@10.0.0.61 "curl -I http://10.0.0.30:8200/v1/sys/health"
   ```

## Likely Root Causes 🔍

Based on the symptoms, the most probable issues are:

1. **Token Not Actually Used**: Nomad config might have token but not using it
2. **Token Expired**: Generated token might have short TTL
3. **Token Missing Policies**: Token lookup might show policies aren't attached
4. **Nomad Not Connecting to Vault**: Servers might not be able to reach Vault cluster
5. **Configuration Not Applied**: Despite Ansible run, config might not be active

## Next Steps 📋

1. Verify token validity and policies (most critical)
2. Test token can read secrets directly
3. Check Nomad server logs for Vault errors
4. Verify configuration is actually deployed
5. If token is invalid/expired, regenerate with longer TTL
6. If policies missing, recreate token with correct policies

## Reference Commands

### Vault Operations
```bash
# Source credentials file
source .credentials

# Or manually set
export VAULT_ADDR=http://10.0.0.30:8200
export VAULT_TOKEN=hvs.YOUR_TOKEN_HERE
```

### Nomad Operations  
```bash
export NOMAD_ADDR=http://10.0.0.50:4646
```

### Useful Paths
- Nomad server config: `/etc/nomad.d/nomad.hcl` on servers
- Ansible vault_token: `ansible/inventory/group_vars/nomad_servers.yml`
- Template: `ansible/roles/nomad-server/templates/nomad-server.hcl.j2`

---
*Last Updated: 2026-02-04*
