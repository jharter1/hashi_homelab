# HashiCorp Vault - Deployment & Integration Guide

**Last Updated**: February 15, 2026  
**Status**: ✅ OPERATIONAL - JWT Workload Identity Fully Configured

> **Quick Reference**: For common commands, see [CHEATSHEET.md](CHEATSHEET.md)

## Overview

HashiCorp Vault provides centralized secrets management for the homelab, enabling:

- **Secrets Storage**: Application credentials, API keys, database passwords
- **Dynamic Secrets**: Database credentials with automatic rotation
- **PKI/CA**: Internal certificate authority for TLS certificates
- **Nomad Integration**: Automatic secret injection into containerized workloads

### Current Infrastructure

```
Hub Vault Cluster (10.0.0.30-32)
├── vault-1 (10.0.0.30) - Primary/Leader
├── vault-2 (10.0.0.31) - Follower
└── vault-3 (10.0.0.32) - Follower

Storage: Raft Integrated Storage (HA, no external dependencies)
Authentication: JWT workload identity from Nomad
Service Discovery: Consul (10.0.0.50)
```

### Integration Status ✅

- **Vault Cluster**: 3 nodes, HA with Raft storage, healthy and unsealed
- **JWT Auth Backend**: Configured at `jwt-nomad/` for Nomad workload identity
- **KV v2 Secrets**: Enabled at `secret/` path with PostgreSQL passwords
- **Nomad Integration**: Working - automatic 1h token acquisition and renewal
- **Policies**: `nomad-workloads` (read access) and `nomad-server` (token management)
- **Jobs**: Successfully reading secrets with Vault templates

---

## Deployment

### Prerequisites

1. **Packer Template**: Debian Nomad server template (ID 9500) exists
2. **Proxmox Access**: SSH and API access to Proxmox host
3. **Network**: IPs 10.0.0.30-32 available
4. **Ansible**: Inventory and playbooks configured

### Quick Deployment

**Option 1: Automated (Recommended)**

```bash
# Complete deployment in one command
task vault:deploy:full

# What it does:
# 1. Creates 3 VMs with Terraform
# 2. Waits for VMs to boot (60s)
# 3. Deploys Consul for service discovery
# 4. Deploys and initializes Vault HA cluster
# 5. Saves credentials to ansible/.vault-hub-credentials
```

**Option 2: Step-by-Step**

```bash
# Step 1: Configure Terraform variables
cp terraform/environments/hub/terraform.tfvars.example terraform/environments/hub/terraform.tfvars
nano terraform/environments/hub/terraform.tfvars
# Update: ssh_public_key, proxmox nodes, template IDs

# Step 2: Deploy VMs
task vault:tf:apply

# Step 3: Wait for VMs to boot
sleep 60

# Step 4: Deploy Consul (for service discovery)
task vault:deploy:consul

# Step 5: Deploy Vault cluster
task vault:deploy:vault

# Step 6: Credentials saved automatically
# Location: ansible/.vault-hub-credentials
# BACK UP THIS FILE IMMEDIATELY!
```

### Post-Deployment Verification

```bash
# Source credentials
source ansible/.vault-hub-credentials

# Check cluster health
vault status

# Check all nodes
task vault:status
# Or manually:
VAULT_ADDR=http://10.0.0.31:8200 vault status
VAULT_ADDR=http://10.0.0.32:8200 vault status

# Test functionality
vault secrets enable -path=secret kv-v2
vault kv put secret/test hello=world
vault kv get secret/test

# Access Web UI
open http://10.0.0.30:8200
# Login with root token from ansible/.vault-hub-credentials
```

### Raft Cluster Management

**How Raft Storage Works:**
- **Integrated Storage**: No external dependencies (no Consul storage backend needed)
- **Quorum**: Requires majority (2 of 3 nodes) operational
- **Leader Election**: Automatic leader election on failure
- **Data Replication**: All data replicated across all nodes

**Check Raft Peers:**
```bash
vault operator raft list-peers

# Expected output:
Node      Address           State     Voter
----      -------           -----     -----
vault-1   10.0.0.30:8201   leader    true
vault-2   10.0.0.31:8201   follower  true
vault-3   10.0.0.32:8201   follower  true
```

### Unsealing

**Initial Unseal (Automatic):**
The deployment playbook automatically unseals all nodes using keys from `.vault-hub-credentials`.

**Manual Unseal After Reboot:**
```bash
# Option 1: Use Taskfile
task vault:unseal

# Option 2: Manual unseal
source ansible/.vault-hub-credentials

# Unseal each node (threshold=1 for homelab)
for i in 30 31 32; do
  VAULT_ADDR=http://10.0.0.$i:8200 vault operator unseal $VAULT_UNSEAL_KEY_1
done
```

---

## Nomad Integration

### Architecture

The homelab uses **JWT workload identity** (modern approach, no server tokens required):

```
Nomad Job → Task Identity (JWT) → Vault JWT Auth → Vault Token → Secrets
```

**How It Works:**
1. Nomad generates JWT for each task using its workload identity
2. Task exchanges JWT for Vault token via `jwt-nomad/` auth backend
3. Vault token has `nomad-workloads` policy attached
4. Task uses token to read secrets from `secret/data/*` paths
5. Token automatically renewed every 1 hour

### Current Configuration

**Vault JWT Auth Backend:**
```bash
# Configured at jwt-nomad/ with:
- JWKS URL: http://10.0.0.50:4646/.well-known/jwks.json
- Bound audiences: ["vault.io"]
- Default lease: 30m
```

**Vault Policies:**
```hcl
# nomad-workloads policy
path "secret/data/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/*" {
  capabilities = ["list"]
}

path "pki_int/issue/service" {
  capabilities = ["create", "update"]
}
```

**Nomad Server Configuration:**
```hcl
# /etc/nomad.d/nomad.hcl on 10.0.0.50-52
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

### Setup Steps (If Starting Fresh)

#### 1. Enable JWT Auth Backend

```bash
export VAULT_ADDR=http://10.0.0.30:8200
export VAULT_TOKEN=<root-token>

# Enable JWT auth
vault auth enable -path=jwt-nomad jwt

# Configure JWT provider
vault write auth/jwt-nomad/config \
  jwks_url="http://10.0.0.50:4646/.well-known/jwks.json" \
  jwt_supported_algs="RS256" \
  default_role="nomad-workloads"
```

#### 2. Create Policies

```bash
# Create nomad-workloads policy
vault policy write nomad-workloads - <<EOF
# Read secrets for Nomad jobs
path "secret/data/*" {
  capabilities = ["read", "list"]
}

# List secret paths
path "secret/metadata/*" {
  capabilities = ["list"]
}

# Issue PKI certificates
path "pki_int/issue/service" {
  capabilities = ["create", "update"]
}
EOF

# Create nomad-server policy (if needed)
vault policy write nomad-server - <<EOF
# Allow token creation
path "auth/token/create" {
  capabilities = ["create", "update"]
}

# Allow token renewal
path "auth/token/renew-self" {
  capabilities = ["update"]
}
EOF
```

#### 3. Create JWT Role

```bash
vault write auth/jwt-nomad/role/nomad-workloads \
  role_type="jwt" \
  bound_audiences="vault.io" \
  user_claim="nomad_job_id" \
  user_claim_json_pointer=true \
  claim_mappings="/nomad_namespace=nomad_namespace,/nomad_job_id=nomad_job_id,/nomad_task=nomad_task" \
  token_policies="nomad-workloads" \
  token_period="30m" \
  token_explicit_max_ttl=0
```

#### 4. Configure Nomad Servers

Edit Ansible configuration:
```bash
# Edit ansible/roles/nomad-server/templates/nomad-server.hcl.j2
# Add or update vault block (should already be there)
```

Apply configuration:
```bash
cd ansible
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags nomad-server

# Restart Nomad servers
ssh ubuntu@10.0.0.50 "sudo systemctl restart nomad"
ssh ubuntu@10.0.0.51 "sudo systemctl restart nomad"
ssh ubuntu@10.0.0.52 "sudo systemctl restart nomad"
```

#### 5. Verify Integration

```bash
# Check Nomad can reach Vault
nomad operator api /v1/operator/vault/config

# Check a running job's allocation
ALLOC_ID=$(nomad job status postgresql | grep running | awk '{print $1}' | head -1)
nomad alloc status $ALLOC_ID | grep Vault

# Should see: "Vault: new Vault token acquired"
```

---

## Using Vault in Nomad Jobs

### Basic Pattern

```hcl
job "example" {
  group "app" {
    task "server" {
      driver = "docker"
      
      # Enable Vault integration
      vault {
        policies = ["nomad-workloads"]
      }
      
      # Read secrets via template
      template {
        destination = "secrets/db.env"
        env         = true
        data        = <<EOH
DB_PASSWORD={{ with secret "secret/data/postgres/myapp" }}{{ .Data.data.password }}{{ end }}
EOH
      }
      
      config {
        image = "myapp:latest"
      }
    }
  }
}
```

### PostgreSQL Example

```hcl
job "postgresql" {
  group "postgres" {
    task "postgres" {
      driver = "docker"
      
      vault {
        policies = ["nomad-workloads"]
      }
      
      template {
        destination = "secrets/postgres.env"
        env         = true
        data        = <<EOH
POSTGRES_PASSWORD={{ with secret "secret/data/postgres/admin" }}{{ .Data.data.password }}{{ end }}
EOH
      }
      
      config {
        image = "postgres:16-alpine"
      }
    }
  }
}
```

### Important Notes

**Every task needs vault {} block:**
```hcl
# ❌ WRONG - Even sidecar tasks need it
task "log-shipper" {
  driver = "docker"
  # Missing vault {} block will cause "Missing: vault.read" errors
}

# ✅ CORRECT - All tasks that use templates need vault
task "log-shipper" {
  driver = "docker"
  vault {
    policies = ["nomad-workloads"]
  }
}
```

**Secret path format:**
```hcl
# KV v2 uses /data/ in the path
# Storage: secret/postgres/admin
# Access: secret/data/postgres/admin

{{ with secret "secret/data/postgres/admin" }}
  {{ .Data.data.password }}  # Note: .Data.data
{{ end }}
```

---

## Secrets Management

### Storing Secrets

**Create database passwords:**
```bash
# Generate secure password
PASSWORD=$(openssl rand -base64 32)

# Store in Vault
vault kv put secret/postgres/myapp password="$PASSWORD"

# Verify
vault kv get secret/postgres/myapp
```

**Bulk secret creation:**
```bash
# Script to create all PostgreSQL secrets
for db in admin freshrss gitea nextcloud authelia grafana; do
  vault kv put secret/postgres/$db password="$(openssl rand -base64 32)"
done
```

### Reading Secrets

**From CLI:**
```bash
# Read full secret
vault kv get secret/postgres/admin

# Get specific field
vault kv get -field=password secret/postgres/admin

# JSON output
vault kv get -format=json secret/postgres/admin
```

**From Nomad job templates:**
```hcl
# Single field
{{ with secret "secret/data/postgres/admin" }}{{ .Data.data.password }}{{ end }}

# Multiple fields
{{ with secret "secret/data/myapp/config" }}
API_KEY={{ .Data.data.api_key }}
API_SECRET={{ .Data.data.api_secret }}
{{ end }}
```

### Updating Secrets

```bash
# Update existing secret (preserves other fields)
vault kv patch secret/postgres/admin password="new-password"

# Replace entire secret
vault kv put secret/postgres/admin password="new-password" username="postgres"

# Rotate database passwords
./scripts/rotate-db-passwords.fish
```

### Secret Organization

**Current structure:**
```
secret/
├── postgres/
│   ├── admin
│   ├── freshrss
│   ├── gitea
│   ├── nextcloud
│   ├── authelia
│   └── grafana
├── authelia/
│   └── config (jwt_secret, session_secret, encryption_key)
└── smtp/
    └── gmail (app_password)
```

**Best practices:**
- Group related secrets by service
- Use consistent naming (lowercase, underscores)
- Document required fields for each secret path
- Avoid storing secrets in job files (use Vault!)

---

## PKI / Certificate Authority

### Setup (If Not Already Configured)

**Enable PKI engines:**
```bash
# Root CA (10 year)
vault secrets enable pki
vault secrets tune -max-lease-ttl=87600h pki

# Intermediate CA (5 year)  
vault secrets enable -path=pki_int pki
vault secrets tune -max-lease-ttl=43800h pki_int
```

**Generate root CA:**
```bash
vault write -field=certificate pki/root/generate/internal \
  common_name="Homelab Root CA" \
  ttl=87600h > root_ca.crt
```

**Generate intermediate CA:**
```bash
# Generate CSR
vault write -field=csr pki_int/intermediate/generate/internal \
  common_name="Homelab Intermediate CA" \
  > pki_intermediate.csr

# Sign with root
vault write -field=certificate pki/root/sign-intermediate \
  csr=@pki_intermediate.csr \
  format=pem_bundle \
  ttl=43800h > intermediate.cert.pem

# Import signed cert
vault write pki_int/intermediate/set-signed \
  certificate=@intermediate.cert.pem
```

**Create PKI role:**
```bash
vault write pki_int/roles/service \
  allowed_domains="home,homelab.local,lab.hartr.net" \
  allow_subdomains=true \
  ttl=720h \
  max_ttl=720h
```

### Issuing Certificates

**Manual certificate issuance:**
```bash
# Issue certificate
vault write pki_int/issue/service \
  common_name="myservice.home" \
  ttl=720h

# Output includes:
# - certificate (PEM)
# - issuing_ca (PEM)
# - private_key (PEM)
# - serial_number
```

**Via Nomad template (currently has issues, see Troubleshooting):**
```hcl
# This pattern is not yet fully working
template {
  data = <<EOH
{{ with secret "pki_int/issue/service" "common_name=*.home" "ttl=720h" }}
{{ .Data.certificate }}{{ end }}
EOH
  destination = "local/tls.crt"
}
```

---

## Troubleshooting

### Issue: Jobs Can't Read Secrets - "Missing: vault.read"

**Symptom:**
```
Template failed: Missing: vault.read(secret/data/postgres/admin)
```

**Causes & Solutions:**

1. **Missing `vault {}` block** - Add to EVERY task that needs secrets:
   ```hcl
   task "mytask" {
     vault {
       policies = ["nomad-workloads"]
     }
   }
   ```

2. **Wrong secret path** - KV v2 requires `/data/` in path:
   ```hcl
   # ❌ WRONG
   {{ with secret "secret/postgres/admin" }}
   
   # ✅ CORRECT  
   {{ with secret "secret/data/postgres/admin" }}
   ```

3. **Policy doesn't allow path** - Update Vault policy:
   ```bash
   vault policy write nomad-workloads - <<EOF
   path "secret/data/*" {
     capabilities = ["read", "list"]
   }
   EOF
   ```

### Issue: PostgreSQL Secrets at Wrong Path

**Problem:** Secrets stored at `secret/postgres/*` but policy only allows `secret/nomad/*`

**Solution A - Update Policy (Recommended):**
```bash
vault policy write nomad-workloads - <<EOF
path "secret/data/nomad/*" {
  capabilities = ["read", "list"]
}

path "secret/data/postgres/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/*" {
  capabilities = ["list"]
}
EOF
```

**Solution B - Reorganize Secrets:**
```bash
# Move secrets under secret/nomad/
for db in admin freshrss gitea nextcloud authelia grafana; do
  PASSWORD=$(vault kv get -field=password secret/postgres/$db)
  vault kv put secret/nomad/postgres/$db password="$PASSWORD"
done

# Update job files to use: secret/data/nomad/postgres/*
```

### Issue: PKI Certificate Issuance via Templates Fails

**Problem:** Manual PKI issuance works, but Nomad templates fail:
```hcl
{{ with secret "pki_int/issue/service" "common_name=*.home" }}...{{ end }}
```

**Status:** This is a known limitation. PKI write operations via Nomad templates require different handling than KV reads.

**Workarounds:**
1. **Pre-issue certificates** and store in Vault KV:
   ```bash
   vault write -format=json pki_int/issue/service common_name="*.home" ttl=720h \
     | jq -r '.data.certificate' \
     | vault kv put secret/certs/wildcard-home certificate=-
   ```

2. **Use cert-manager** or external PKI tooling

3. **Use Let's Encrypt** for public domains (Traefik integration)

### Issue: Token Renewal Causing Hourly Restarts

**Problem:** Vault tokens have 1h TTL, causing tasks to restart hourly for renewal.

**Solution:** Increase TTL in Nomad server config:
```hcl
vault {
  default_identity {
    aud = ["vault.io"]
    ttl = "8h"  # Restart every 8 hours instead of 1
  }
}
```

Then restart Nomad servers.

### Issue: Vault Cluster Sealed After Reboot

**Solution:**
```bash
# Use automated unseal
task vault:unseal

# Or manual:
source ansible/.vault-hub-credentials
for i in 30 31 32; do
  VAULT_ADDR=http://10.0.0.$i:8200 vault operator unseal $VAULT_UNSEAL_KEY_1
done
```

**Future: Auto-unseal** with cloud KMS or Transit seal

---

## Maintenance

### Backup Strategy

**Critical files to backup:**
```bash
# Vault credentials (MOST IMPORTANT)
ansible/.vault-hub-credentials

# Terraform state (if using local state)
terraform/environments/hub/terraform.tfstate

# Raft data (on Vault nodes)
ssh ubuntu@10.0.0.30 "sudo tar czf /tmp/vault-data.tar.gz /opt/vault/data"
```

**Vault snapshot (recommended):**
```bash
# Take Raft snapshot
vault operator raft snapshot save vault-snapshot-$(date +%Y%m%d).snap

# Restore from snapshot
vault operator raft snapshot restore vault-snapshot-20260215.snap
```

### Rotating Root Token

```bash
# Generate new root token (requires unseal keys)
vault operator generate-root -init

# Follow prompts, use unseal key(s)
vault operator generate-root -nonce=<nonce> <unseal-key>

# Decode OTP
vault operator generate-root \
  -decode=<encoded-token> \
  -otp=<otp>
```

### Monitoring

**Check cluster health:**
```bash
# All nodes status
task vault:status

# Raft cluster
vault operator raft list-peers

# Seal status
vault status

# Active connections
vault read sys/internal/counters/activity
```

**Audit logs:**
```bash
# Enable audit logging
vault audit enable file file_path=/var/log/vault/audit.log

# View audit log
ssh ubuntu@10.0.0.30 "sudo tail -f /var/log/vault/audit.log"
```

---

## Migration Notes

### From Single Node to HA Cluster

If migrating from single-node Vault to HA:

1. **Take snapshot** of single node
2. **Deploy HA cluster** (see Deployment section)
3. **Restore data** to new cluster leader
4. **Update Nomad servers** with new Vault address
5. **Restart Nomad** to pickup new config
6. **Verify jobs** can still read secrets

### From Token-Based to JWT Workload Identity

If migrating from old token-based approach:

1. **Configure JWT auth** (see Nomad Integration section)
2. **Update Nomad server config** with `jwt_auth_backend_path`
3. **Remove `token` field** from vault block
4. **Add `default_identity`** block
5. **Restart Nomad servers**
6. **Redeploy jobs** to get JWT tokens
7. **Verify** secret access still works

---

## Security Best Practices

1. **Protect Credentials File**: `ansible/.vault-hub-credentials` is the keys to the kingdom
2. **Rotate Root Token**: Generate new root token periodically (quarterly)
3. **Audit Logging**: Enable file audit backend for compliance
4. **Network Isolation**: Vault cluster should be on trusted network
5. **TLS Everywhere**: Use TLS for Vault API (currently HTTP for homelab)
6. **Least Privilege**: Create separate policies for different workload types
7. **Secret Rotation**: Rotate database passwords quarterly
8. **Backup Regularly**: Raft snapshots + credentials file backup

---

## Reference

- **Quick Commands**: See [CHEATSHEET.md](CHEATSHEET.md)
- **Vault Documentation**: https://developer.hashicorp.com/vault/docs
- **Nomad Vault Integration**: https://developer.hashicorp.com/nomad/docs/integrations/vault-integration  
- **JWT Auth Method**: https://developer.hashicorp.com/vault/docs/auth/jwt

### Common Paths

- **Vault UI**: http://10.0.0.30:8200
- **Credentials**: `ansible/.vault-hub-credentials`
- **Server Config**: `ansible/roles/nomad-server/templates/nomad-server.hcl.j2`
- **Vault Config**: `/etc/vault.d/vault.hcl` (on Vault nodes)
- **Raft Data**: `/opt/vault/data/` (on Vault nodes)
