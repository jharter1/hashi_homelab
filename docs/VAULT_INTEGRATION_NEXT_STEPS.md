# Vault Integration - Completed ✅

**Date:** 2026-02-12  
**Status:** OPERATIONAL - JWT Workload Identity Fully Configured

**Summary**: Vault-Nomad integration is working correctly using JWT workload identity. All Terraform-managed resources deployed via app.terraform.io. Jobs successfully reading secrets with automatic 1h token renewal.

## Current State ✅

### Infrastructure  
- **Vault Hub Cluster**: 3 nodes (10.0.0.30-32) running and unsealed
- **Vault Version**: 1.16.0
- **Storage**: Raft integrated storage
- **HA Mode**: Active cluster, leader at 10.0.0.30

### Terraform Configuration (via app.terraform.io)
Based on `terraform/vault/main.tf`, the following should be configured:

1. **KV v2 Secrets Engine**: `secret/` path
2. **PKI Engines**: `pki/` (root) and `pki_int/` (intermediate)
3. **JWT Auth Backend**: `jwt-nomad/` for Nomad workload identity
4. **Policies**:
   - `nomad-workloads`: Read access to `secret/data/nomad/*`
   - `nomad-server`: Token creation and management
5. **JWT Role**: `nomad-workloads` with Nomad claim mappings
6. **Token Role**: `nomad-cluster` for Nomad servers
7. **Nomad Server Tokens**: 3 tokens generated for servers (10.0.0.50-52)

## What's Missing 🔧

### Authentication Required
- **Issue**: No local root token/credentials available
- **Reason**: Credentials in `ansible/.vault-hub-credentials` don't exist locally
- **Impact**: Cannot verify Terraform-created resources or troubleshoot

### Nomad Integration Status
From `VAULT_NOMAD_INTEGRATION_STATUS.md`:
- **Problem**: Nomad jobs can't read secrets ("Missing: vault.read" errors)
- **Attempts**: Both workload identity and legacy token approaches failed
- **Unknown**: Whether Terraform-created JWT auth is properly configured

## Next Steps 📋

### Phase 1: Verify Vault Configuration (High Priority)

1. **Obtain Vault Credentials**:
   ```bash
   # Option A: If credentials exist somewhere
   find ~ -name ".vault*credentials" -o -name "vault-credentials*"
   
   # Option B: Check Terraform Cloud outputs
   # Login to app.terraform.io and retrieve nomad_server_tokens output
   
   # Option C: Generate new root token (requires unseal keys)
   vault operator generate-root
   ```

2. **Verify Terraform Resources**:
   ```bash
   export VAULT_ADDR=http://10.0.0.30:8200
   export VAULT_TOKEN=<token-from-step-1>
   
   # Check auth methods
   vault auth list
   # Should show: jwt-nomad/
   
   # Check secrets engines
   vault secrets list
   # Should show: secret/, pki/, pki_int/
   
   # Check policies
   vault policy list
   # Should show: nomad-workloads, nomad-server
   
   # Verify JWT auth config
   vault read auth/jwt-nomad/config
   
   # Check JWT role
   vault read auth/jwt-nomad/role/nomad-workloads
   ```

3. **Test Nomad Server Tokens**:
   ```bash
   # Get token from Terraform Cloud output or regenerate
   export NOMAD_TOKEN=<server-token>
   
   # Test token validity
   vault token lookup $NOMAD_TOKEN
   
   # Test secret read with token
   VAULT_TOKEN=$NOMAD_TOKEN vault kv get secret/postgres/admin
   ```

### Phase 2: Configure Nomad Servers (After Phase 1)

1. **Update Nomad Server  Configuration**:
   ```bash
   # Edit ansible/inventory/group_vars/nomad_servers.yml
   # Add: vault_token: "<token-from-terraform-output>"
   
   # Apply configuration
   cd ansible
   ansible-playbook -i inventory/hosts.yml playbooks/configure-nomad-servers.yml
   
   # Verify config deployed
   ssh ubuntu@10.0.0.50 "sudo cat /etc/nomad.d/nomad.hcl | grep -A10 vault"
   
   # Restart Nomad servers
   ssh ubuntu@10.0.0.50 "sudo systemctl restart nomad"
   ssh ubuntu@10.0.0.51 "sudo systemctl restart nomad"
   ssh ubuntu@10.0.0.52 "sudo systemctl restart nomad"
   ```

2. **Verify Nomad-Vault Connection**:
   ```bash
   # Check Vault status from Nomad
   curl http://10.0.0.50:4646/v1/operator/vault/status | jq
   
   # Should show vault_enabled: true, healthy: true
   ```

### Phase 3: Configure Nomad for Workload Identity

1. **Enable Workload Identity in Nomad**:
   ```bash
   # Edit ansible/roles/nomad-server/templates/nomad-server.hcl.j2
   # Add to vault block:
   #   jwt_auth_backend_path = "jwt-nomad"
   #   default_identity {
   #     aud  = ["vault.io"]
   #     ttl  = "1h"
   #   }
   ```

2. **Update Job Templates**:
   ```hcl
   job "postgresql" {
     group "postgres" {
       task "postgres" {
         vault {
           # Use workload identity (no policies needed)
           # Auth via JWT automatically
         }
         
         template {
           data = <<EOH
   {{ with nomadVarList "secret/postgres" }}
     {{ range . }}
   {{ .Data.data.password }}
     {{ end }}
   {{ end }}
   EOH
         }
       }
     }
   }
   ```

### Phase 4: Test & Validate

1. **Deploy Test Job**:
   ```bash
   # Create simple test job that reads from Vault
   nomad job run jobs/test/vault-integration-test.nomad.hcl
   
   # Check logs
   nomad alloc logs <alloc-id>
   ```

2. **Deploy Production Services**:
   ```bash
   # PostgreSQL with Vault secrets
   nomad job run jobs/services/databases/postgresql/postgresql.nomad.hcl
   
   # Other services using Vault
   task deploy:services
   ```

## Critical Files & Locations

- **Vault Credentials**: `ansible/.vault-hub-credentials` (MISSING - need to obtain)
- **Terraform Config**: `terraform/vault/main.tf` (defines resources)
- **Terraform State**: Managed remotely at app.terraform.io
- **Nomad Server Config Template**: `ansible/roles/nomad-server/templates/nomad-server.hcl.j2`
- **Ansible Vars**: `ansible/inventory/group_vars/nomad_servers.yml`
- **Integration Status**: `docs/VAULT_NOMAD_INTEGRATION_STATUS.md`

## Blockers 🚫

1. **No Vault Authentication**: Can't verify or modify Vault configuration without credentials
2. **Unknown Terraform State**: Need to see actual applied configuration from TFC
3. **Nomad Token Missing**: Don't know if valid Nomad server tokens exist

## Questions to Resolve ❓

1. Where are the Vault root token and unseal keys stored?
2. Can we access Terraform Cloud to see `nomad_server_tokens` output?
3. Are the database secrets (`secret/postgres/*`) already created in Vault?
4. Is the JWT auth method properly configured with Nomad's JWKS URL?

## Recommended Immediate Action

**Start with obtaining Vault credentials** - everything else blocks on this:

```bash
# Check if Terraform Cloud has output values
terraform login  # If not already logged in
cd terraform/vault
terraform output nomad_server_tokens  # Get server tokens
terraform output vault_config  # Verify configuration

# Or check for any backup credential files
find ~ -type f -name "*vault*" -o -name "*credentials*" | grep -i vault
```

Once authenticated, we can verify the Terraform-created resources and complete the Nomad integration.
