# Vault Integration Quick Reference

## Common Commands

### Vault Status & Health

```bash
# Check primary node
vault status

# Check all cluster nodes
task vault:status

# List Raft peers
vault operator raft list-peers
```

### Working with Secrets

```bash
# Enable KV v2 engine
vault secrets enable -path=secret kv-v2

# Write secret
vault kv put secret/myapp/config api_key=abc123 db_password=secret

# Read secret
vault kv get secret/myapp/config
vault kv get -format=json secret/myapp/config | jq -r '.data.data.api_key'

# List secrets
vault kv list secret/myapp

# Delete secret
vault kv delete secret/myapp/config
```

### From Nomad Jobs

```hcl
job "example" {
  vault {
    policies = ["nomad-workloads"]
  }
  
  task "app" {
    template {
      data = <<EOH
{{ with secret "secret/myapp/config" }}
API_KEY={{ .Data.data.api_key }}
DB_PASS={{ .Data.data.db_password }}
{{ end }}
EOH
      destination = "secrets/app.env"
      env = true
    }
  }
}
```

## Task Reference

### Deployment

```bash
task vault:deploy:full      # Complete deployment (VMs + Consul + Vault)
task vault:tf:apply          # Deploy VMs only
task vault:deploy:consul     # Deploy Consul service discovery
task vault:deploy:vault      # Deploy Vault HA cluster
```

### Operations

```bash
task vault:status            # Check all nodes
task vault:unseal            # Unseal all nodes after reboot
task vault:test              # Run functionality test
```

### Infrastructure

```bash
task vault:tf:plan           # Preview infrastructure changes
task vault:tf:destroy        # Destroy Vault cluster VMs
```

## Environment Variables

```bash
# Primary cluster address
export VAULT_ADDR=http://10.0.0.30:8200

# Root token (from credentials file)
export VAULT_TOKEN=hvs.XXXXXXXXXXXXXXXXXXXXX

# Or source all credentials
source ansible/.vault-hub-credentials
```

## Ansible Playbooks

```bash
# Deploy Consul for service discovery
ansible-playbook -i ansible/inventory/hub.yml ansible/playbooks/deploy-hub-consul.yml

# Deploy Vault cluster
ansible-playbook -i ansible/inventory/hub.yml ansible/playbooks/deploy-hub-vault.yml

# Unseal cluster
ansible-playbook -i ansible/inventory/hub.yml ansible/playbooks/unseal-vault.yml

# Configure Nomad integration (Phase 2)
ansible-playbook -i ansible/inventory/hub.yml ansible/playbooks/update-nomad-client-vault.yml
```

## Useful Scripts

```bash
# Configure Vault-Nomad integration
./scripts/configure-vault-nomad-integration.fish

# Migrate secrets from dev to hub
./scripts/migrate-vault-dev-to-hub.fish

# Set Proxmox password for Packer/Terraform
source scripts/set-proxmox-password.fish
```

## Cluster Endpoints

- **Primary API**: http://10.0.0.30:8200
- **Node 2**: http://10.0.0.31:8200
- **Node 3**: http://10.0.0.32:8200
- **Service in Consul**: vault.service.consul

## File Locations

```
terraform/environments/hub/          # Hub cluster infrastructure
ansible/inventory/hub.yml            # Hub cluster inventory
ansible/playbooks/deploy-hub-*.yml   # Vault deployment playbooks
ansible/roles/vault/                 # Vault Ansible role
ansible/.vault-hub-credentials       # Credentials (gitignored)
docs/VAULT.md                       # Comprehensive deployment & integration guide
```

## Troubleshooting Quick Fixes

```bash
# Vault won't start
ssh root@10.0.0.30 "journalctl -u vault -f"

# Unseal after reboot
task vault:unseal

# Check Raft cluster
vault operator raft list-peers

# Verify Consul integration
vault read sys/health
curl http://10.0.0.50:8500/v1/health/service/vault
```

## Security Best Practices

1. **Never commit** `.vault-hub-credentials` to git (it's gitignored)
2. **Back up** unseal keys and root token securely
3. **Rotate** root token after initial setup
4. **Use policies** instead of root token for applications
5. **Enable audit logging** in production
6. **Use TLS** in production environments
7. **Consider auto-unseal** for production

## Next Steps After Deployment

See `ansible/TODO.md` for the complete Vault integration roadmap:

- Phase 1: ✅ Hub cluster deployment (current)
- Phase 2: 🔄 Nomad-Vault integration (JWT auth, policies)
- Phase 3: 🔄 OIDC authentication (optional)
- Phase 4: 🔄 Production hardening (TLS, audit, backup)
