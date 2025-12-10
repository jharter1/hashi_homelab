# Ansible Configuration Management

This directory contains Ansible playbooks and roles for managing the Nomad homelab cluster.

## Quick Start

```bash
cd ansible

# Test connectivity
ansible-playbook playbooks/test-connectivity.yml

# Apply Docker configuration only
ansible-playbook playbooks/configure-docker.yml

# Apply full site configuration
ansible-playbook playbooks/site.yml

# Dry run (check mode)
ansible-playbook playbooks/site.yml --check
```

## Directory Structure

```
ansible/
├── ansible.cfg              # Ansible configuration
├── inventory/
│   └── hosts.yml           # Inventory of all nodes
├── playbooks/
│   ├── test-connectivity.yml    # Test connectivity
│   ├── configure-docker.yml     # Docker configuration only
│   └── site.yml                 # Full site configuration
├── roles/
│   ├── base-system/        # Base system setup (DNS, NFS, packages)
│   └── nomad-client/       # Nomad client configuration
└── templates/              # Shared templates (if needed)
```

## Inventory

The inventory defines 6 nodes:
- **Nomad Servers** (3): 10.0.0.50-52
- **Nomad Clients** (3): 10.0.0.60-62

All nodes use the `ubuntu` user and SSH keys for authentication.

## Roles

### base-system
Configures base system settings for all nodes:
- Installs essential packages (nfs-common, curl, jq, etc.)
- Configures DNS (if systemd-resolved exists)
- Mounts NAS storage (clients only)
- Creates host volume directories (clients only)

### nomad-client
Configures Nomad client nodes:
- Deploys `/etc/nomad.d/nomad.hcl` from template
- Defines all host volumes (grafana, loki, minio, prometheus, registry)
- Configures Docker plugin
- Manages Nomad service

## Common Operations

### Apply Docker Configuration
This is a quick win that doesn't require restarting Nomad:
```bash
ansible-playbook playbooks/configure-docker.yml
```

### Update Nomad Client Configuration
This will restart Nomad clients (jobs will reschedule):
```bash
ansible-playbook playbooks/site.yml --tags nomad
```

### Test Changes Without Applying
Always test with `--check` first:
```bash
ansible-playbook playbooks/site.yml --check --diff
```

### Target Specific Hosts
```bash
# Single host
ansible-playbook playbooks/site.yml --limit nomad-client-1

# Group of hosts
ansible-playbook playbooks/site.yml --limit nomad_clients

# Multiple hosts
ansible-playbook playbooks/site.yml --limit nomad-client-1,nomad-client-2
```

### Verify Configuration
```bash
# Check a specific file on all clients
ansible nomad_clients -m shell -a "cat /etc/docker/daemon.json"

# Check Nomad status
ansible nomad_clients -m shell -a "systemctl status nomad" --become
```

## Variables

Key variables are defined in:
- `inventory/hosts.yml` - Host and group variables
- `roles/*/defaults/main.yml` - Role defaults

Important variables:
- `docker_registry_mirror`: `http://registry.home:5000`
- `nas_mount_source`: `10.0.0.220:/mnt/HD/HD_a2/PVE-VM-Storage`
- `nas_mount_point`: `/mnt/nas`
- `nomad_server_addresses`: List of server IPs

## Migration from Terraform

This Ansible setup is designed to gradually replace cloud-init configuration:

1. ✅ **Docker Configuration** - Now managed by Ansible
2. ✅ **Base System Setup** - DNS, NFS, packages managed by Ansible
3. ✅ **Nomad Client Config** - Templated and managed by Ansible
4. 🔄 **Next Steps**:
   - Simplify cloud-init templates to minimal SSH/network setup
   - Add nomad-server role
   - Add consul role
   - Move all HashiCorp binaries to Ansible

## Best Practices

1. **Always test with --check first** before applying changes to production
2. **Use --diff** to see exactly what will change
3. **Limit scope** with `--limit` when testing new changes
4. **Version control** all playbook and role changes
5. **Document** any manual steps still required

## Troubleshooting

### SSH Connection Issues
```bash
# Test SSH connectivity
ansible all -m ping

# Check SSH with verbose output
ansible all -m ping -vvv
```

### Ansible Warnings
The warning about `ansible.posix` collection version can be ignored or fixed by updating Ansible.

### Nomad Service Issues
If Nomad fails to restart, check logs:
```bash
ansible nomad_clients -m shell -a "journalctl -u nomad -n 50" --become
```
