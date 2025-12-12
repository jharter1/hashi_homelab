# Ansible Configuration Management Roadmap

## ✅ Current State (Completed)

### Infrastructure Separation
- ✅ Terraform handles ONLY VM provisioning
- ✅ Ansible handles ALL configuration management
- ✅ Idempotent, repeatable configuration
- ✅ Easy to update running systems

### Working Playbooks & Roles
- ✅ `playbooks/site.yml` - Full site configuration
- ✅ `playbooks/configure-docker.yml` - Docker configuration only
- ✅ `playbooks/test-connectivity.yml` - Connectivity testing
- ✅ `roles/base-system/` - DNS, NFS, packages, host volumes
- ✅ `roles/nomad-client/` - Nomad client configuration with host volumes
- ✅ `roles/consul/` - Consul installation and configuration
- ✅ `roles/nomad-server/` - Nomad server configuration
- ✅ `roles/hashicorp-binaries/` - HashiCorp tool installation
- ✅ `roles/node-exporter/` - Prometheus node exporter

### Inventory & Organization
- ✅ Static inventory with groups (nomad_servers, nomad_clients)
- ✅ Group variables for cluster configuration
- ✅ Host volumes configured via Ansible templates

---

## 🚧 Vault Integration Roadmap

The Vault integration is partially implemented and ready to be completed. Here's what exists and what's needed:

### What's Already Built

**Infrastructure (Terraform)**:
- ✅ `terraform/environments/hub/` - Hub environment for Vault cluster
  - 3-node Vault cluster configuration
  - Terraform state: `terraform-hub.tfstate`
  - Outputs for CA certs
- ✅ `terraform/vault/` - Vault provider configuration module
- ✅ Vault integration in dev environment (`vault.tf`, `vault-variables.tf`)

**Ansible Playbooks**:
- ✅ `playbooks/deploy-hub-consul.yml` - Deploy Consul for Vault cluster
- ✅ `playbooks/deploy-hub-vault.yml` - Deploy Vault cluster
- ✅ `playbooks/install-vault.yml` - Install Vault on Nomad servers
- ✅ `playbooks/unseal-vault.yml` - Unseal Vault instances
- ✅ `playbooks/update-nomad-client-vault.yml` - Configure Nomad clients for Vault
- ✅ `playbooks/update-nomad-oidc.yml` - OIDC configuration

**Inventory**:
- ✅ `inventory/hub.yml` - Hub cluster inventory (10.0.0.30-32)
- ✅ `inventory/group_vars/vault_servers.yml` - Vault server configuration

**Helper Scripts**:
- ✅ `scripts/setup-vault.fish` - Vault setup automation
- ✅ `scripts/configure-vault-nomad-integration.fish` - Integration helper
- ✅ `scripts/migrate-vault-dev-to-hub.fish` - Migration script

**Roles**:
- ✅ `roles/vault/` - Vault installation and configuration role

### What Needs to Be Completed

#### Phase 1: Hub Vault Cluster Deployment
- [ ] **Test and validate hub environment**
  - [ ] Ensure terraform/environments/hub/ deploys successfully
  - [ ] Verify 3-node Vault cluster formation
  - [ ] Document any needed fixes
  
- [ ] **Complete Vault initialization workflow**
  - [ ] Test `playbooks/deploy-hub-consul.yml`
  - [ ] Test `playbooks/deploy-hub-vault.yml`
  - [ ] Verify `playbooks/unseal-vault.yml` works across cluster
  - [ ] Document unseal key management process

- [ ] **Add Taskfile tasks for hub deployment**
  ```yaml
  vault:deploy:hub:
    desc: "Deploy 3-node Vault cluster on hub"
    cmds:
      - cd terraform/environments/hub && terraform apply
      - ansible-playbook -i ansible/inventory/hub.yml playbooks/deploy-hub-consul.yml
      - ansible-playbook -i ansible/inventory/hub.yml playbooks/deploy-hub-vault.yml
  ```

#### Phase 2: Vault-Nomad Integration
- [ ] **Configure Nomad to use Vault for secrets**
  - [ ] Test `playbooks/update-nomad-client-vault.yml`
  - [ ] Configure Nomad servers to authenticate with Vault
  - [ ] Set up Vault policy for Nomad
  - [ ] Enable Vault token renewal
  
- [ ] **Create Vault PKI backend**
  - [ ] Configure PKI secrets engine
  - [ ] Generate intermediate CA
  - [ ] Create role for Nomad workload certificates
  
- [ ] **Update job templates to use Vault**
  - [ ] Add Vault stanza to job specifications
  - [ ] Document template syntax for secrets
  - [ ] Create example jobs using Vault secrets

#### Phase 3: OIDC Integration (Optional)
- [ ] **Configure OIDC authentication**
  - [ ] Test `playbooks/update-nomad-oidc.yml`
  - [ ] Set up OIDC provider (e.g., Authentik, Keycloak)
  - [ ] Configure Nomad ACLs with OIDC
  - [ ] Document login workflow

#### Phase 4: Documentation & Best Practices
- [ ] **Update main README**
  - [ ] Add Vault architecture diagram
  - [ ] Document Vault deployment process
  - [ ] Add Vault troubleshooting section
  
- [ ] **Create Vault-specific docs**
  - [ ] `docs/VAULT_DEPLOYMENT.md` - Step-by-step deployment
  - [ ] `docs/VAULT_NOMAD_INTEGRATION.md` - Integration guide
  - [ ] Update existing `docs/VAULT_INTEGRATION.md`
  
- [ ] **Security hardening**
  - [ ] Document backup/recovery procedures
  - [ ] Implement automated unseal (transit backend or cloud KMS)
  - [ ] Set up audit logging
  - [ ] Configure Vault policies for least privilege

### Migration Strategy

**Option 1: Separate Vault Cluster (Recommended)**
- Deploy hub environment with dedicated Vault cluster (10.0.0.30-32)
- Keep Nomad cluster separate (10.0.0.50-52 servers, 10.0.0.60-62 clients)
- Nomad workloads authenticate to Vault cluster
- Better separation of concerns, more HA

**Option 2: Collocated Vault**
- Install Vault on existing Nomad servers
- Simpler deployment, fewer VMs
- Less separation between compute and secrets
- Good for resource-constrained homelabs

### Testing Checklist
- [ ] Vault cluster forms correctly
- [ ] Vault unseals automatically after reboot
- [ ] Nomad can authenticate to Vault
- [ ] Jobs can retrieve secrets from Vault
- [ ] Vault tokens renew automatically
- [ ] Audit logs are being written
- [ ] Backup/restore process works

---

## 📚 Reference Links

- [Vault-Nomad Integration](https://developer.hashicorp.com/nomad/docs/integrations/vault)
- [Vault PKI Secrets Engine](https://developer.hashicorp.com/vault/docs/secrets/pki)
- [Nomad ACL with OIDC](https://developer.hashicorp.com/nomad/docs/configuration/acl/auth-methods)
- [Vault Auto-unseal](https://developer.hashicorp.com/vault/docs/concepts/seal#auto-unseal)
│   ├── docker/                # Docker setup
│   ├── node_exporter/         # Monitoring agent
│   └── nfs_client/            # NAS mount setup
├── playbooks/
│   ├── site.yml               # Run everything
│   ├── base.yml
│   ├── hashicorp.yml
│   ├── nomad-servers.yml
│   ├── nomad-clients.yml
│   ├── docker.yml
│   ├── monitoring.yml
│   └── validate.yml
├── templates/
│   ├── consul-server.hcl.j2
│   ├── consul-client.hcl.j2
│   ├── nomad-server.hcl.j2
│   ├── nomad-client.hcl.j2
│   └── docker-daemon.json.j2
└── ansible.cfg
```

### 12. Variables to Parameterize
- [ ] NAS mount path and NFS server IP
- [ ] Consul/Nomad server IPs
- [ ] Datacenter name
- [ ] Network CIDR ranges
- [ ] Resource allocations
- [ ] Registry URL/port
- [ ] Grafana/Loki/Prometheus versions

### 13. Benefits After Migration
- ✅ Update any configuration without rebuilding VMs
- ✅ Idempotent operations (safe to run multiple times)
- ✅ Clearer separation of concerns
- ✅ Easier to test individual components
- ✅ Better documentation (playbooks are self-documenting)
- ✅ Faster iteration on configuration changes
- ✅ Secrets management with Ansible Vault
- ✅ Easy rollback capabilities

### 14. Migration Strategy
1. **Phase 1**: Keep Terraform as-is, create Ansible playbooks alongside
2. **Phase 2**: Test Ansible playbooks on existing infrastructure
3. **Phase 3**: Simplify Terraform cloud-init to bare minimum
4. **Phase 4**: Use Terraform for provisioning, Ansible for everything else
5. **Phase 5**: Document the new workflow

### 15. Quick Wins to Start With
- [ ] Create Ansible inventory from current infrastructure
- [ ] Write playbook to update Docker daemon.json on all nodes
- [ ] Write playbook to update Nomad client configs
- [ ] Write playbook to restart services safely
- [ ] Test on one node before rolling out

### 16. Documentation Needed
- [ ] README for ansible/ directory
- [ ] Playbook usage examples
- [ ] Common operations guide
- [ ] Troubleshooting guide
- [ ] Variables reference

## Next Immediate Steps
1. Create `ansible/` directory structure
2. Create initial `inventory/hosts.yml` with your 6 nodes
3. Create `ansible.cfg` with basic settings
4. Write a simple playbook to test connectivity
5. Implement Docker configuration playbook (quick win!)
