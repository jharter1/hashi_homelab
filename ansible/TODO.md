# Ansible Migration TODO

## Current State
- Terraform handles VM provisioning AND configuration
- Configuration is embedded in cloud-init templates
- Manual steps required for some services
- Limited idempotency for configuration changes

## Goal
- Terraform handles ONLY VM provisioning
- Ansible handles ALL configuration management
- Idempotent, repeatable configuration
- Easy to update running systems

## Migration Tasks

### 1. Infrastructure Separation
- [ ] Strip all configuration logic from Terraform cloud-init templates
- [ ] Keep only minimal cloud-init for basic SSH access and network setup
- [ ] Terraform outputs should provide inventory information for Ansible

### 2. Ansible Inventory Setup
- [ ] Create dynamic inventory script to read from Nomad/Consul
- [ ] Or create static inventory with groups (nomad-servers, nomad-clients, etc.)
- [ ] Set up host variables for IP addresses, roles, etc.

### 3. Base System Configuration (Playbook: `base.yml`)
- [ ] Configure DNS resolvers
- [ ] Set up NFS mounts to NAS
- [ ] Configure system packages and updates
- [ ] Set up host volumes directories

### 4. HashiCorp Stack Installation (Playbook: `hashicorp.yml`)
- [ ] Install Consul (server and client modes)
- [ ] Install Nomad (server and client modes)
- [ ] Install Vault (optional, future)
- [ ] Set up systemd services
- [ ] Configure for proper startup order

### 5. Nomad Server Configuration (Playbook: `nomad-servers.yml`)
- [ ] Deploy server configuration files
- [ ] Configure bootstrap expect count
- [ ] Set up telemetry
- [ ] Configure Consul integration

### 6. Nomad Client Configuration (Playbook: `nomad-clients.yml`)
- [ ] Deploy client configuration files
- [ ] Configure host volumes (NAS mounts)
- [ ] Set up node classes and metadata
- [ ] Configure Docker plugin settings
- [ ] Configure resource reservations

### 7. Docker Configuration (Playbook: `docker.yml`)
- [ ] Install Docker on client nodes
- [ ] Configure daemon.json with:
  - [ ] Registry mirrors (local registry)
  - [ ] Insecure registries
  - [ ] Log rotation settings
  - [ ] Storage driver
- [ ] Restart Docker service
- [ ] Add nomad user to docker group

### 8. Monitoring Stack (Playbook: `monitoring.yml`)
- [ ] Install and configure Node Exporter
- [ ] Register services in Consul
- [ ] Configure Prometheus scrape configs
- [ ] Set up Alloy for log collection

### 9. Service Deployment (Playbook: `services.yml`)
- [ ] Deploy Traefik job
- [ ] Deploy MinIO job
- [ ] Deploy Loki job
- [ ] Deploy Prometheus job
- [ ] Deploy Grafana job
- [ ] Deploy Docker Registry job
- [ ] Deploy Alloy system job
- [ ] Or use `nomad job run` directly (decision needed)

### 10. Testing & Validation (Playbook: `validate.yml`)
- [ ] Check Consul cluster health
- [ ] Check Nomad cluster health
- [ ] Verify all clients connected
- [ ] Test service discovery
- [ ] Verify Docker registry mirror working
- [ ] Check monitoring stack

### 11. Ansible Structure

```
ansible/
├── inventory/
│   ├── hosts.yml              # Static inventory
│   └── group_vars/
│       ├── all.yml            # Global vars
│       ├── nomad_servers.yml
│       └── nomad_clients.yml
├── roles/
│   ├── base/                  # Base system setup
│   ├── consul/                # Consul installation/config
│   ├── nomad/                 # Nomad installation/config
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
