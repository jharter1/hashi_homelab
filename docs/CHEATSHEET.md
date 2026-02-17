# Homelab Quick Reference

**Last Updated**: February 15, 2026

Quick commands for common operations across the homelab. For comprehensive guides, see the main documentation files.

---

## Cluster Management

### Check Nomad Cluster Memory

```fish
# Quick memory check (Fish shell)
for node_name in dev-nomad-client-1 dev-nomad-client-2 dev-nomad-client-3 dev-nomad-client-4 dev-nomad-client-5 dev-nomad-client-6
  set node_id (curl -s http://10.0.0.50:4646/v1/nodes | python3 -c "import sys, json; nodes = json.load(sys.stdin); print([n['ID'] for n in nodes if '$node_name' == n['Name']][0])")
  curl -s http://10.0.0.50:4646/v1/node/$node_id | python3 -c "import sys, json; n = json.load(sys.stdin); mem = n.get('NodeResources', {}).get('Memory', {}).get('MemoryMB', 0); print('$node_name: ' + str(mem) + ' MB (' + str(round(mem/1024, 2)) + ' GB)')"
end

# Check actual VM memory
for ip in 10.0.0.60 10.0.0.61 10.0.0.62 10.0.0.63 10.0.0.64 10.0.0.65
  ssh ubuntu@$ip "echo -n '$ip: ' && free -h | grep Mem"
end
```

### Check All Job Statuses

```bash
# List all jobs and their status
curl -s http://10.0.0.50:4646/v1/jobs | python3 -c "import sys, json; jobs = json.load(sys.stdin); [print(f\"{j['Name']}: {j['Status']}\") for j in jobs]"

# Find dead services
nomad job status -address=http://10.0.0.50:4646 | grep dead
```

### Restart Services After Client Reboot

```fish
# Restart all services
for job in jobs/services/*.nomad.hcl
  nomad job run -address=http://10.0.0.50:4646 $job
end

# Or specific service
nomad job run -address=http://10.0.0.50:4646 jobs/services/homepage.nomad.hcl
```

---

## Nomad

### Deploy Jobs

```bash
# Deploy all services
nomad run jobs/services/*.nomad.hcl

# Watch job status
nomad job status -verbose whoami

# Check allocations
nomad job allocs prometheus

# View logs
nomad alloc logs -f <alloc-id>
nomad alloc logs -stderr <alloc-id>

# Restart a job
nomad job restart prometheus
```

### Job Management

```bash
# Stop job
nomad job stop prometheus

# Stop and purge (clean removal)
nomad job stop -purge prometheus

# Validate job file
nomad job validate jobs/services/prometheus.nomad.hcl

# Plan deployment
nomad job plan jobs/services/prometheus.nomad.hcl
```

---

## Consul

### Service Discovery

```bash
# List all services
consul catalog services

# Get service details
consul catalog service prometheus

# Check service health
consul health service prometheus

# Query DNS
dig @127.0.0.1 -p 8600 prometheus.service.consul
```

### Cluster Status

```bash
# List members
consul members

# Check leader
consul operator raft list-peers
```

---

## Vault - Quick Commands

### Status & Health

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
# Enable KV v2 engine (one-time)
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

# Get specific field
vault kv get -field=password secret/postgres/grafana
```

### Vault in Nomad Jobs

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

### Vault Task Commands

```bash
# Deployment
task vault:deploy:full      # Complete deployment (VMs + Consul + Vault)
task vault:tf:apply          # Deploy VMs only
task vault:deploy:consul     # Deploy Consul service discovery
task vault:deploy:vault      # Deploy Vault HA cluster

# Operations
task vault:status            # Check all nodes
task vault:unseal            # Unseal all nodes after reboot
task vault:test              # Run functionality test

# Infrastructure
task vault:tf:plan           # Preview infrastructure changes
task vault:tf:destroy        # Destroy Vault cluster VMs
```

### Unseal Vault Cluster

```bash
# Unseal all nodes (manual)
for ip in 10.0.0.30 10.0.0.31 10.0.0.32
  vault operator unseal -address=http://$ip:8200
end

# Or use task
task vault:unseal

# Or use Ansible
ansible-playbook -i ansible/inventory/hub.yml ansible/playbooks/unseal-vault.yml
```

### Environment Setup

```bash
# Primary cluster address
export VAULT_ADDR=http://10.0.0.30:8200

# Root token (from credentials file)
export VAULT_TOKEN=hvs.XXXXXXXXXXXXXXXXXXXXX

# Or source all credentials
source ansible/.vault-hub-credentials
```

---

## Authelia SSO - Quick Commands

### Initial Setup

```bash
# 1. Generate secrets and store in Vault
./scripts/setup-authelia-secrets.fish

# 2. Generate password hash
./scripts/generate-authelia-password.fish

# 3. Deploy everything
./scripts/deploy-authelia-sso.fish
```

### Manual Deployment

```bash
# Deploy Redis
nomad job run jobs/services/redis.nomad.hcl

# Deploy Authelia
nomad job run jobs/services/authelia.nomad.hcl
```

### Testing & Monitoring

```bash
# Test protection status
./scripts/test-authelia-protection.fish

# Check Authelia health
curl https://authelia.lab.hartr.net/api/health

# Check job status
nomad job status authelia
nomad job status redis

# View logs
nomad alloc logs -f $(nomad job allocs authelia | grep running | awk '{print $1}' | head -1)

# Check Consul registration
consul catalog service authelia
consul catalog service redis
```

### Protect a Service

```bash
# 1. Edit service job file
nano jobs/services/SERVICE.nomad.hcl

# 2. Add middleware tag
tags = [
  # ... existing tags ...
  "traefik.http.routers.SERVICE.middlewares=authelia@consulcatalog",
]

# 3. Redeploy
nomad job run jobs/services/SERVICE.nomad.hcl

# 4. Test (should redirect to Authelia)
curl -I https://SERVICE.lab.hartr.net
```

### User Management

```bash
# Generate new password hash
./scripts/generate-authelia-password.fish

# Add user to authelia.nomad.hcl
nano jobs/services/authelia.nomad.hcl
# Add to users_database.yml section

# Redeploy
nomad job run jobs/services/authelia.nomad.hcl
```

### Troubleshooting

```bash
# Login loop - check Redis connection
redis-cli -h redis.service.consul PING
nomad alloc logs -f $(nomad job allocs authelia | grep running | awk '{print $1}' | head -1) | grep session

# 502 errors - check Authelia health
consul catalog service authelia
curl http://authelia.service.consul:9091/api/health

# Access denied - check logs
nomad alloc logs -f $(nomad job allocs authelia | grep running | awk '{print $1}' | head -1) | grep "access control"

# Service not protected - verify middleware
nomad job inspect SERVICE | grep middleware
```

---

## Configuration Management

### Sync Configs to Cluster

```bash
# Sync all external configs to NAS
task configs:sync

# Direct Ansible
cd ansible && ansible-playbook playbooks/sync-configs.yml
```

### Validate Before Deploy

```bash
# Validate all
task validate:all

# Validate specific
nomad job validate jobs/services/prometheus.nomad.hcl
yamllint configs/observability/prometheus/prometheus.yml
```

---

## Taskfile Commands

### Build Infrastructure

```bash
# Build VM templates
task build:debian:base      # Base cloud image (VM 9400)
task build:debian:server    # Server template (VM 9500)
task build:debian:client    # Client template (VM 9501)

# Bootstrap everything
task bootstrap              # Full cluster deployment

# Or step-by-step
task tf:apply               # Provision VMs
task ansible:configure      # Configure services
task deploy:all             # Deploy Nomad jobs
```

### Deployment Tasks

```bash
# Terraform
task tf:plan
task tf:apply
task tf:destroy

# Ansible
task ansible:configure
task ansible:ping

# Jobs
task deploy:all
task deploy:system
task deploy:services
```

---

## Troubleshooting Quick Fixes

### Nomad

```bash
# Job won't start
nomad job status SERVICE
nomad alloc status <alloc-id>
nomad alloc logs -stderr <alloc-id>

# Service "dead" after reboot
nomad job run jobs/services/SERVICE.nomad.hcl

# Check node resources
nomad node status -verbose <node-id>
```

### Vault

```bash
# Vault won't start
ssh root@10.0.0.30 "journalctl -u vault -f"

# Unseal after reboot
task vault:unseal

# Check Raft cluster
vault operator raft list-peers

# Verify Consul integration
curl http://10.0.0.50:8500/v1/health/service/vault
```

### Consul

```bash
# Service not discovered
consul catalog service SERVICE
consul health service SERVICE

# Agent issues
consul members
ssh ubuntu@10.0.0.60 "sudo systemctl status consul"
```

### Authelia

```bash
# Login loop
redis-cli -h redis.service.consul PING

# Cookie issues (check domain has leading dot)
# In authelia.nomad.hcl:
# domain: .lab.hartr.net  # Correct
# domain: lab.hartr.net   # Wrong

# API endpoints getting protected
# Add bypass rules in access_control.rules
```

---

## Cluster Endpoints

### Nomad Cluster (Dev)
- **Servers**: 10.0.0.50-52:4646
- **Clients**: 10.0.0.60-65
- **UI**: http://10.0.0.50:4646

### Vault Cluster (Hub)
- **Primary**: http://10.0.0.30:8200
- **Node 2**: http://10.0.0.31:8200
- **Node 3**: http://10.0.0.32:8200
- **Service**: vault.service.consul

### Consul
- **Dev Servers**: 10.0.0.50-52:8500
- **Hub**: 10.0.0.30-32:8500
- **UI**: http://10.0.0.50:8500

### Services (via Traefik)
- **Authelia**: https://authelia.lab.hartr.net
- **Grafana**: https://grafana.lab.hartr.net
- **Prometheus**: https://prometheus.lab.hartr.net
- **Homepage**: https://home.lab.hartr.net

---

## File Locations

```
# Infrastructure
terraform/environments/dev/          # Dev cluster Terraform
terraform/environments/hub/          # Hub cluster Terraform
ansible/inventory/                   # Cluster inventories
ansible/playbooks/                   # Automation playbooks

# Jobs
jobs/system/                         # System jobs (Traefik, Alloy)
jobs/services/                       # Service jobs

# Configs (external)
configs/infrastructure/              # Traefik
configs/observability/               # Prometheus, Grafana, Loki, Alertmanager
configs/auth/                        # Authelia (future)

# Data (NFS)
/mnt/nas/prometheus_data/            # Prometheus TSDB
/mnt/nas/postgres_data/              # PostgreSQL
/mnt/nas/grafana_data/               # Grafana dashboards
/mnt/nas/configs/                    # Synced configs

# Credentials (gitignored)
ansible/.vault-hub-credentials       # Vault credentials
packer/variables/proxmox-host1.pkrvars.hcl  # Proxmox credentials
```

---

## Related Documentation

- [README.md](../README.md) - Main project documentation
- [QUICKSTART.md](QUICKSTART.md) - Getting started guide
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Comprehensive troubleshooting
- [VAULT.md](VAULT.md) - Vault deployment and integration
- [AUTHELIA.md](AUTHELIA.md) - SSO authentication setup
- [PROMETHEUS.md](PROMETHEUS.md) - Monitoring and metrics
- [POSTGRESQL.md](POSTGRESQL.md) - Database management
- [PHASE1.md](PHASE1.md) - Config externalization guide
