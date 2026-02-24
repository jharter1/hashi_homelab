# Ansible Playbook Organization

This directory contains Ansible playbooks for managing the HashiCorp homelab infrastructure. Playbooks are organized by function to enable fast, targeted operations instead of always running the full configuration stack.

## 📊 Playbook Speed Reference

| Playbook | Speed | Frequency | Purpose |
|----------|-------|-----------|---------|
| `install-hashicorp-binaries.yml` | 🐌 5-10 min | Once/upgrades | Install Consul, Nomad, Vault binaries |
| `site.yml` | 🐌 5-10 min | Once/full rebuild | Full cluster configuration (all roles) |
| `configure-base-system.yml` | ⚡ 30-60 sec | Rare | DNS, packages, NFS, volumes |
| `configure-services.yml` | ⚡ 1-2 min | Occasional | Consul + Nomad service configs |
| `update-nomad-configs.yml` | ⚡ 30-45 sec | **Frequent** | Update configs, restart if changed |
| `restart-services.yml` | ⚡⚡ 10-20 sec | **Very Frequent** | Quick service restart |

## 🎯 Quick Start - Common Scenarios

### I need to restart services (troubleshooting)
```bash
task ansible:restart              # All services
task ansible:restart:nomad        # Nomad only
task ansible:restart:consul       # Consul only
```

### I changed a Nomad/Consul config template
```bash
task ansible:update:configs       # All nodes
task ansible:update:configs:servers  # Servers only
task ansible:update:configs:clients  # Clients only
```

### I'm setting up new nodes
```bash
# Full bootstrap (first time)
task bootstrap  # Uses site.yml internally

# OR manual step-by-step
task ansible:install:binaries     # Once: install HashiCorp tools
task ansible:configure:base       # Configure base system
task ansible:configure:services   # Configure Consul/Nomad
```

### I upgraded HashiCorp tool versions
```bash
# Update variables/common.pkrvars.hcl with new versions first
task build:debian:server          # Rebuild templates
task build:debian:client
task tf:destroy && task tf:apply  # Recreate VMs
task ansible:install:binaries     # Install new binaries
task ansible:configure:services   # Reconfigure services
```

## 📁 Playbook Catalog

### Core Infrastructure (Decomposed)

#### `install-hashicorp-binaries.yml`
**When to use:**
- First-time setup on new nodes
- Upgrading Consul/Nomad/Vault versions
- Node exporter installation

**What it does:**
- Downloads and installs Consul, Nomad, Vault binaries
- Installs Prometheus Node Exporter
- Creates log directories

**Speed:** 🐌 5-10 minutes (network downloads)

**Task shortcuts:**
```bash
task ansible:install:binaries
```

#### `configure-base-system.yml`
**When to use:**
- Setting up new nodes after binary installation
- Adding new NFS volumes
- Updating DNS configuration
- Installing base packages

**What it does:**
- Configures DNS in resolv.conf
- Installs base packages (nfs-common, curl, vim, etc.)
- Mounts NAS storage
- Creates host volume directories
- Syncs homepage configs

**Speed:** ⚡ 30-60 seconds

**Task shortcuts:**
```bash
task ansible:configure:base
```

#### `configure-services.yml`
**When to use:**
- Setting up new nodes after base configuration
- Major Consul/Nomad configuration changes
- Cluster topology changes (add/remove nodes)

**What it does:**
- Creates Consul/Nomad system users and directories
- Deploys Consul/Nomad configuration files from templates
- Creates systemd service units
- Starts and enables services
- Waits for services to become healthy

**Speed:** ⚡ 1-2 minutes

**Task shortcuts:**
```bash
task ansible:configure:services
```

#### `update-nomad-configs.yml` ⭐ **MOST USED**
**When to use:**
- Modified Nomad/Consul configuration templates in roles
- Added/removed Vault integration
- Updated ACL settings
- Changed datacenter/region settings
- Any config file changes in `roles/*/templates/*.j2`

**What it does:**
- Re-renders config templates from latest role definitions
- Restarts services ONLY if configs changed
- Waits for services to stabilize
- Verifies cluster health

**Speed:** ⚡ 30-45 seconds

**Task shortcuts:**
```bash
task ansible:update:configs           # All nodes
task ansible:update:configs:servers   # Servers only
task ansible:update:configs:clients   # Clients only
```

**Example workflow:**
```bash
# 1. Edit template
vim ansible/roles/nomad-client/templates/nomad-client.hcl.j2

# 2. Apply to clients
task ansible:update:configs:clients

# 3. Verify
NOMAD_ADDR=http://10.0.0.50:4646 nomad node status
```

#### `restart-services.yml` ⭐ **FASTEST**
**When to use:**
- Services are stuck or unresponsive
- Quick troubleshooting
- After manual config edits (not recommended, use update-nomad-configs.yml instead)

**What it does:**
- Restarts Consul and/or Nomad systemd services
- Waits for ports to become available
- Shows service status

**Speed:** ⚡⚡ 10-20 seconds

**Task shortcuts:**
```bash
task ansible:restart              # All services
task ansible:restart:consul       # Consul only
task ansible:restart:nomad        # Nomad only

# Advanced filtering
ansible-playbook ansible/playbooks/restart-services.yml --limit nomad_servers
```

#### `site.yml` (Original Full Stack)
**When to use:**
- First-time cluster bootstrap (via `task bootstrap`)
- Complete infrastructure rebuild
- When you want the "nuclear option"

**What it does:**
- Runs ALL roles in sequence:
  - hashicorp-binaries (slow)
  - base-system
  - node-exporter
  - consul
  - nomad-server/nomad-client

**Speed:** 🐌 5-10 minutes

**Task shortcuts:**
```bash
task ansible:configure  # Still available, but consider decomposed playbooks
```

**Note:** After initial bootstrap, prefer using decomposed playbooks for faster operations.

### Specialized Playbooks (Existing)

#### `configure-docker.yml`
Configure Docker daemon with registry mirrors and insecure registries.

```bash
task ansible:docker
```

#### `sync-configs.yml` / `sync-homepage-config.yml`
Sync configuration files from local machine to NAS storage.

```bash
task homepage:sync
```

#### `test-connectivity.yml`
Test Ansible connectivity and gather facts from all nodes.

```bash
task ansible:test
```

#### Vault Integration (WIP)
- `deploy-hub-vault.yml` - Deploy Vault on hub nodes
- `unseal-vault.yml` - Unseal Vault cluster
- `configure-vault-jwt-auth.yml` - Configure JWT auth for Nomad
- `configure-nomad-vault-integration.yml` - Enable Vault integration in Nomad
- `update-nomad-*-vault*.yml` - Update Vault-related configurations

#### Tailscale
- `deploy-tailscale.yml` - Deploy Tailscale for remote access

```bash
task tailscale:deploy
task tailscale:deploy:traefik  # Traefik node only
```

## 🔄 Migration from site.yml

### Old Workflow (Slow)
```bash
# Every time you needed to update anything:
task ansible:configure  # 5-10 minutes, reinstalls binaries every time
```

### New Workflow (Fast)
```bash
# Most common operations:
task ansible:restart                # 10-20 seconds
task ansible:update:configs         # 30-45 seconds

# Occasional operations:
task ansible:configure:base         # 30-60 seconds
task ansible:configure:services     # 1-2 minutes

# Rare operations (upgrades):
task ansible:install:binaries       # 5-10 minutes
```

## 🎨 Playbook Design Patterns

### Idempotency
All playbooks are idempotent - safe to run multiple times. Tasks use:
- `creates:` parameter for commands
- `when:` conditions for conditional execution
- `changed_when:` for accurate change reporting
- `notify:` handlers for service restarts

### Restart Strategies
1. **restart-services.yml**: Unconditional restart (always restarts)
2. **update-nomad-configs.yml**: Conditional restart (only if config changed)
3. **configure-services.yml**: Initial setup + start services

### Template Paths
Templates are referenced using relative paths from playbook directory:
```yaml
template:
  src: "{{ playbook_dir }}/../roles/nomad-client/templates/nomad-client.hcl.j2"
  dest: /etc/nomad.d/nomad.hcl
```

## 🚀 Performance Tips

1. **Use specific playbooks** instead of site.yml after initial bootstrap
2. **Limit hosts** with `--limit` flag:
   ```bash
   ansible-playbook playbooks/restart-services.yml --limit nomad-client-1
   ```
3. **Use tags** where available:
   ```bash
   ansible-playbook playbooks/restart-services.yml --tags nomad
   ```
4. **Check facts first** with `test-connectivity.yml` if nodes might be down
5. **Update configs in parallel** - all decomposed playbooks support parallel execution

## 📝 Adding New Playbooks

When creating new playbooks, follow this template:
```yaml
---
# Playbook description
# Run this when:
#  - Use case 1
#  - Use case 2
#
# Usage: ansible-playbook ansible/playbooks/your-playbook.yml
#
# Speed estimate: X minutes/seconds

- name: Descriptive play name
  hosts: target_host_group
  become: yes
  gather_facts: yes
  
  tasks:
    # Your tasks here
  
  post_tasks:
    - name: Verify operation
      # Verification task
```

Then add to [Taskfile.yml](../../Taskfile.yml):
```yaml
  ansible:your:task:
    desc: "Brief description"
    cmds:
      - |
        cd ansible && ansible-playbook playbooks/your-playbook.yml
```

## 🔗 Related Documentation

- [Taskfile.yml](../../Taskfile.yml) - All available tasks
- [ansible/roles/](../roles/) - Role definitions and templates
- [docs/NEW_SERVICES_DEPLOYMENT.md](../../docs/NEW_SERVICES_DEPLOYMENT.md) - Service deployment patterns
- [docs/TROUBLESHOOTING.md](../../docs/TROUBLESHOOTING.md) - Common issues and solutions
