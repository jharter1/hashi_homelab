# Upgrade to Latest HashiCorp Versions

## Date
December 11, 2025

## Overview
Upgrading all HashiCorp stack components to their latest stable versions to resolve compatibility issues, particularly the Vault PKI template integration problem with Nomad workload identity.

## Version Changes

### Before
- **Consul**: 1.20.1
- **Nomad**: 1.10.3 (running 1.11.0 in production)
- **Vault**: 1.16.0 (hashicorp-binaries), 1.18.3 (vault role)

### After
- **Consul**: 1.22.1 (latest stable, released Dec 2025)
- **Nomad**: 1.11.1 (latest stable, released Dec 2025)
- **Vault**: 1.21.1 (latest stable, released Dec 2025)

## Key Benefits

### 1. Nomad 1.11.1
- **Workload Identity Improvements**: Enhanced integration with Vault
- **Consul Template Updates**: May include fixes for `vault.write()` operations
- **Bug Fixes**: Numerous stability improvements since 1.10.3
- **Security Patches**: Latest security updates

### 2. Vault 1.21.1
- **PKI Improvements**: Enhanced PKI secrets engine
- **JWT/OIDC Updates**: Better workload identity support
- **Performance**: Improved cluster performance
- **Compatibility**: Better integration with Nomad 1.11.x

### 3. Consul 1.22.1
- **Service Mesh**: Enhanced Connect features
- **Performance**: Better scalability for service discovery
- **Security**: Latest security patches

## Breaking Changes & Considerations

### Vault 1.16 → 1.21
- **Review**: Check Vault upgrade notes for 1.17, 1.18, 1.19, 1.20, 1.21
- **Raft Storage**: No breaking changes expected for Raft backend
- **PKI Engine**: Enhanced features, backward compatible
- **API Changes**: Minor improvements, generally backward compatible

### Nomad 1.10 → 1.11
- **Workload Identity**: Enhanced features (already using these)
- **Consul Template**: Embedded version updated (may fix our PKI issue!)
- **API**: No breaking changes for our use cases
- **Jobs**: Existing job specifications should work without modification

### Consul 1.20 → 1.22
- **Service Discovery**: No breaking changes expected
- **Connect**: Enhanced features, backward compatible
- **API**: Minor improvements

## Upgrade Process

### Step 1: Backup Critical Data
```bash
# Backup Vault data
ssh ubuntu@10.0.0.30 "sudo tar -czf /tmp/vault-backup-$(date +%F).tar.gz /opt/vault/data"
scp ubuntu@10.0.0.30:/tmp/vault-backup-*.tar.gz ./backups/

# Backup Nomad data
ssh ubuntu@10.0.0.50 "sudo tar -czf /tmp/nomad-backup-$(date +%F).tar.gz /opt/nomad"
scp ubuntu@10.0.0.50:/tmp/nomad-backup-*.tar.gz ./backups/

# Backup Consul data (if used)
ssh ubuntu@10.0.0.30 "sudo tar -czf /tmp/consul-backup-$(date +%F).tar.gz /opt/consul"
```

### Step 2: Upgrade Vault Cluster (Rolling Upgrade)
Vault supports rolling upgrades for HA clusters:

```bash
# Upgrade Vault nodes one at a time
cd ansible

# Upgrade first Vault node (standby)
ansible-playbook -i inventory/hosts.yml playbooks/deploy-hub-vault.yml \
  --limit vault-node2 -e vault_version=1.21.1

# Verify node rejoined cluster
vault operator raft list-peers

# Upgrade second Vault node (standby)
ansible-playbook -i inventory/hosts.yml playbooks/deploy-hub-vault.yml \
  --limit vault-node3 -e vault_version=1.21.1

# Verify cluster health
vault status

# Step down active node and upgrade
vault operator step-down
ansible-playbook -i inventory/hosts.yml playbooks/deploy-hub-vault.yml \
  --limit vault-node1 -e vault_version=1.21.1

# Verify final cluster state
vault status
vault operator raft list-peers
```

### Step 3: Upgrade Nomad Servers (Rolling Upgrade)
Nomad supports rolling upgrades:

```bash
# Upgrade Nomad servers one at a time
# Start with followers, leader last

# Upgrade server 2
ansible-playbook -i inventory/hosts.yml playbooks/deploy-minimal-nomad.yml \
  --limit nomad-server2 --tags nomad-server -e nomad_version=1.11.1

# Wait for server to rejoin
nomad server members

# Upgrade server 3
ansible-playbook -i inventory/hosts.yml playbooks/deploy-minimal-nomad.yml \
  --limit nomad-server3 --tags nomad-server -e nomad_version=1.11.1

# Upgrade server 1 (leader will transfer)
ansible-playbook -i inventory/hosts.yml playbooks/deploy-minimal-nomad.yml \
  --limit nomad-server1 --tags nomad-server -e nomad_version=1.11.1

# Verify cluster
nomad server members
nomad status
```

### Step 4: Upgrade Nomad Clients
After all servers are upgraded:

```bash
# Drain and upgrade clients one at a time
for client in nomad-client1 nomad-client2 nomad-client3; do
  # Drain node
  nomad node drain -enable -yes $(nomad node status -json | jq -r ".[] | select(.Name==\"$client\") | .ID")
  
  # Upgrade
  ansible-playbook -i inventory/hosts.yml playbooks/deploy-minimal-nomad.yml \
    --limit $client --tags nomad-client -e nomad_version=1.11.1
  
  # Re-enable
  nomad node drain -disable $(nomad node status -json | jq -r ".[] | select(.Name==\"$client\") | .ID")
  
  # Wait for allocations to stabilize
  sleep 30
done
```

### Step 5: Upgrade Consul (If Using)
```bash
# If using Consul for service discovery
ansible-playbook -i inventory/hosts.yml playbooks/deploy-hub-consul.yml \
  -e consul_version=1.22.1
```

## Post-Upgrade Verification

### Vault Checks
```bash
# Check cluster status
vault status
vault operator raft list-peers

# Verify PKI is accessible
vault read pki_int/roles/service

# Test JWT auth
vault read auth/jwt-nomad/role/nomad-workloads

# Check policies
vault policy read nomad-workloads
```

### Nomad Checks
```bash
# Check cluster
nomad server members
nomad node status

# Verify version
nomad version

# Check Vault integration
nomad operator api /v1/agent/self | jq '.config.Vault'

# Test workload identity
nomad job status traefik
nomad alloc status <traefik-alloc-id>
```

### Integration Test
```bash
# Redeploy Traefik to test PKI certificate issuance
nomad job stop -purge traefik
nomad job run jobs/system/traefik.nomad.hcl

# Check allocation
nomad alloc logs <alloc-id> traefik

# Look for successful cert issuance
nomad alloc exec <alloc-id> ls -la /local/
```

## Expected Resolution: PKI Template Issue

The upgrade from Nomad 1.10.3 to 1.11.1 should resolve the Vault PKI template issue because:

1. **Consul Template Update**: Nomad 1.11.x includes an updated version of Consul Template with better Vault workload identity support
2. **Bug Fixes**: Known issues with `vault.write()` operations in templates may be fixed
3. **Enhanced Workload Identity**: Improved token handling for write operations
4. **Vault 1.21 Compatibility**: Better integration between latest Nomad and Vault versions

## Rollback Plan

If issues arise:

### Rollback Vault
```bash
# Stop newer version
sudo systemctl stop vault

# Restore from backup
sudo rm -rf /opt/vault/data
sudo tar -xzf /path/to/vault-backup-*.tar.gz -C /

# Reinstall old version
ansible-playbook -i inventory/hosts.yml playbooks/deploy-hub-vault.yml \
  -e vault_version=1.18.3

# Unseal and verify
vault operator unseal
vault status
```

### Rollback Nomad
```bash
# Reinstall old version on servers
ansible-playbook -i inventory/hosts.yml playbooks/deploy-minimal-nomad.yml \
  --tags nomad-server -e nomad_version=1.10.3

# Reinstall old version on clients
ansible-playbook -i inventory/hosts.yml playbooks/deploy-minimal-nomad.yml \
  --tags nomad-client -e nomad_version=1.10.3
```

## Simplified Upgrade (All at Once - Acceptable Downtime)

If brief downtime is acceptable:

```bash
cd ansible

# Update all HashiCorp binaries
ansible-playbook -i inventory/hosts.yml playbooks/site.yml \
  -e consul_version=1.22.1 \
  -e nomad_version=1.11.1 \
  -e vault_version=1.21.1

# Unseal Vault nodes
./scripts/unseal-vault.sh  # If you have this script

# Verify everything
nomad server members
nomad node status
vault status
```

## Timeline

**Estimated Duration**: 1-2 hours for rolling upgrade, 30 minutes for full cluster restart

**Recommended Window**: Non-production hours

## Success Criteria

- [ ] All Vault nodes running 1.21.1 and healthy
- [ ] All Nomad servers running 1.11.1 and healthy
- [ ] All Nomad clients running 1.11.1 and healthy
- [ ] Consul running 1.22.1 (if applicable)
- [ ] All existing jobs running successfully
- [ ] Vault workload identity tokens being issued
- [ ] **Traefik PKI certificate template renders successfully**
- [ ] No errors in Nomad/Vault logs
- [ ] Vault cluster is sealed=false on all nodes

## References

- [Nomad 1.11 Changelog](https://github.com/hashicorp/nomad/blob/main/CHANGELOG.md)
- [Vault 1.21 Release Notes](https://developer.hashicorp.com/vault/docs/release-notes/1.21.0)
- [Consul 1.22 Release Notes](https://developer.hashicorp.com/consul/docs/release-notes/1.22.x)
- [Nomad Upgrade Guide](https://developer.hashicorp.com/nomad/docs/upgrade)
- [Vault Upgrade Guide](https://developer.hashicorp.com/vault/docs/upgrading)
