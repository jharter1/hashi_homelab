# Vault Hub Cluster Deployment Guide

This guide walks through deploying a 3-node Vault HA cluster on dedicated infrastructure (the "hub" environment).

## Architecture

```
Hub Vault Cluster (10.0.0.30-32)
├── vault-1 (10.0.0.30) - Primary/Leader
├── vault-2 (10.0.0.31) - Follower
└── vault-3 (10.0.0.32) - Follower

Storage: Raft Integrated Storage (HA without external dependencies)
Service Discovery: Consul (running on Nomad servers at 10.0.0.50)
```

## Prerequisites

1. **Packer Template**: Debian Nomad server template (ID 9500) exists
2. **Proxmox Access**: SSH and API access to Proxmox host
3. **Network**: IPs 10.0.0.30-32 available
4. **Ansible**: Inventory and playbooks configured

## Quick Start

### Option 1: Automated Deployment (Recommended)

```bash
# Complete deployment in one command
task vault:deploy:full

# What it does:
# 1. Creates 3 VMs with Terraform
# 2. Waits for VMs to boot
# 3. Deploys Consul for service discovery
# 4. Deploys and initializes Vault HA cluster
# 5. Saves credentials to ansible/.vault-hub-credentials
```

### Option 2: Step-by-Step Deployment

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

# Step 6: Save credentials
# Credentials are automatically saved to: ansible/.vault-hub-credentials
# BACK UP THIS FILE IMMEDIATELY!
```

## Post-Deployment

### 1. Source Credentials

```bash
# Load Vault credentials into your environment
source ansible/.vault-hub-credentials

# Verify connection
vault status
```

### 2. Check Cluster Health

```bash
# Check all nodes
task vault:status

# Or manually:
vault status                                    # Primary node
VAULT_ADDR=http://10.0.0.31:8200 vault status # Node 2
VAULT_ADDR=http://10.0.0.32:8200 vault status # Node 3
```

### 3. Test Vault Functionality

```bash
# Run automated test
task vault:test

# Or manually test:
vault secrets enable -path=secret kv-v2
vault kv put secret/test hello=world
vault kv get secret/test
```

### 4. Access Web UI

Open in browser: http://10.0.0.30:8200

Login with the root token from `ansible/.vault-hub-credentials`

## Raft Cluster Details

### How Raft Storage Works

- **Integrated Storage**: No external dependencies (no Consul storage backend needed)
- **Quorum**: Requires majority (2 of 3 nodes) to be operational
- **Leader Election**: Automatic leader election on failure
- **Data Replication**: All data replicated across nodes

### Checking Raft Peers

```bash
vault operator raft list-peers

# Expected output:
Node      Address           State     Voter
----      -------           -----     -----
vault-1   10.0.0.30:8201   leader    true
vault-2   10.0.0.31:8201   follower  true
vault-3   10.0.0.32:8201   follower  true
```

## Unsealing

### Initial Unseal (Automatic)

The deployment playbook automatically unseals all nodes using the keys saved in `.vault-hub-credentials`.

### Manual Unseal After Reboot

```bash
# Option 1: Use Taskfile
task vault:unseal

# Option 2: Manual unseal
source ansible/.vault-hub-credentials

# Unseal each node (needs 1 key, threshold=1 for homelab)
for i in 30 31 32; do
  VAULT_ADDR=http://10.0.0.$i:8200 vault operator unseal $VAULT_UNSEAL_KEY_1
done
```

### Auto-Unseal (Future Enhancement)

For production, consider:
- Transit auto-unseal using another Vault cluster
- Cloud KMS (AWS, GCP, Azure)
- HSM integration

## Backup & Recovery

### Backup Raft Snapshots

```bash
# Create snapshot
vault operator raft snapshot save vault-backup-$(date +%Y%m%d).snap

# Restore snapshot (if needed)
vault operator raft snapshot restore vault-backup-YYYYMMDD.snap
```

### Backup Credentials

```bash
# Securely store these files:
ansible/.vault-hub-credentials  # Root token + unseal keys

# Consider:
# - Password manager (1Password, Bitwarden)
# - Encrypted USB drive (offline backup)
# - Split keys among team members (Shamir's Secret Sharing)
```

## Troubleshooting

### Node Won't Join Cluster

```bash
# Check logs
ssh root@10.0.0.30 "journalctl -u vault -n 100"

# Verify Raft peers
vault operator raft list-peers

# Remove and re-add peer if needed
vault operator raft remove-peer vault-2
```

### Sealed After Reboot

```bash
# All Vault nodes seal on restart for security
# Unseal them:
task vault:unseal
```

### Can't Connect to Vault

```bash
# Check service status
ssh root@10.0.0.30 "systemctl status vault"

# Check Vault is listening
ssh root@10.0.0.30 "netstat -tulpn | grep 8200"

# Check firewall
ssh root@10.0.0.30 "iptables -L -n | grep 8200"
```

### Split Brain / Multiple Leaders

```bash
# Shouldn't happen with Raft, but if it does:
# 1. Stop Vault on all nodes
# 2. Clear raft data on followers (keep leader's data)
# 3. Start leader first
# 4. Start and rejoin followers
```

## Security Considerations

### Current Setup (Homelab/Dev)

- ✅ Raft HA storage
- ✅ Root token rotation possible
- ⚠️ TLS disabled (HTTP only)
- ⚠️ Manual unsealing
- ⚠️ Single unseal key (threshold=1)

### Production Hardening (TODO)

- [ ] Enable TLS with proper certificates
- [ ] Use auto-unseal (transit or cloud KMS)
- [ ] Increase unseal key threshold (3 of 5)
- [ ] Enable audit logging
- [ ] Configure Vault policies (least privilege)
- [ ] Set up periodic backups
- [ ] Monitor Vault health metrics

## Next Steps

After the hub cluster is deployed, proceed to:

1. **Phase 2**: Configure Nomad-Vault integration
   - Set up JWT auth backend
   - Configure Nomad workload identity
   - Test secret retrieval from jobs

2. **Phase 3** (Optional): OIDC authentication
   - Set up OIDC provider
   - Configure Nomad ACLs

3. **Phase 4**: Production hardening
   - Enable TLS
   - Set up auto-unseal
   - Configure audit logging
   - Document DR procedures

See `ansible/TODO.md` for the complete roadmap.

## References

- [Vault Integrated Storage (Raft)](https://developer.hashicorp.com/vault/docs/concepts/integrated-storage)
- [Vault HA Concepts](https://developer.hashicorp.com/vault/docs/concepts/ha)
- [Vault Operations](https://developer.hashicorp.com/vault/docs/commands)
- [Vault Deployment Guide](https://developer.hashicorp.com/vault/tutorials/operations/deployment-guide)
