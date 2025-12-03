# Ubuntu Base Template

This directory contains the Ubuntu base template for creating HashiCorp-ready VM templates on ProxMox.

## Overview

The Ubuntu base template creates a production-ready Ubuntu 22.04 LTS VM template with:
- Consul, Vault, and Nomad pre-installed
- Docker Engine for container workloads
- Cloud-init support for automated provisioning
- SSH hardening and security best practices
- Optimized for ProxMox virtualization

## Files

- `ubuntu-base.pkr.hcl` - Main Packer template with ProxMox builder
- `http/user-data` - Cloud-init autoinstall configuration
- `http/meta-data` - Cloud-init metadata

## Requirements Met

This template satisfies the following requirements from the specification:

### Requirement 2.1: Base Template with Ubuntu 22.04 LTS
- ✅ Uses Ubuntu 22.04.5 LTS ISO
- ✅ Cloud-init support enabled
- ✅ QEMU guest agent installed

### Requirement 2.4: SSH Hardening and Security
- ✅ SSH hardening via security-hardening.sh
- ✅ Password authentication disabled (configurable)
- ✅ Root login disabled (configurable)
- ✅ Fail2ban configured for SSH protection

### Requirement 5.2: Cloud-init Configuration
- ✅ Network configuration via cloud-init
- ✅ User creation with SSH key support
- ✅ Automated system setup on first boot

### Requirement 6.1: Variable Validation
- ✅ All required variables have validation blocks
- ✅ Format validation for IPs, CIDRs, versions
- ✅ Range validation for memory, cores, disk size
- ✅ Descriptive error messages for validation failures

### Requirement 6.2: Network Settings Validation
- ✅ CIDR validation using cidrhost() function
- ✅ IPv4 address validation with regex
- ✅ DNS server format and count validation
- ✅ VLAN tag range validation

## Quick Start

### Prerequisites

1. Packer installed (v1.9.0 or later)
2. ProxMox host accessible
3. ProxMox API credentials
4. Variable files configured

### Validation

Before building, validate the configuration:

```bash
./packer/validate-ubuntu-base.sh
```

This script checks:
- Packer installation
- Variable files existence
- Template syntax
- Provisioning scripts
- Cloud-init configuration

### Building the Template

1. Set your ProxMox password:
```bash
export PROXMOX_PASSWORD='your-password'
```

2. Build the template:
```bash
packer build \
  -var-file=packer/variables/common.pkrvars.hcl \
  -var-file=packer/variables/proxmox-host1.pkrvars.hcl \
  -var="proxmox_password=$PROXMOX_PASSWORD" \
  packer/templates/ubuntu/ubuntu-base.pkr.hcl
```

### Build Process

The build process takes approximately 20-30 minutes and includes:

1. **ISO Download** - Downloads Ubuntu 22.04.5 LTS ISO
2. **VM Creation** - Creates VM with specified resources
3. **OS Installation** - Automated Ubuntu installation via cloud-init
4. **System Update** - Updates all packages to latest versions
5. **Base Setup** - Configures system, users, directories
6. **HashiCorp Installation** - Installs Consul, Vault, Nomad
7. **Docker Installation** - Installs Docker Engine and plugins
8. **Security Hardening** - Applies SSH and system security
9. **Cleanup** - Removes temporary files and optimizes disk
10. **Template Conversion** - Converts VM to ProxMox template

## Configuration

### Variable Files

The template uses two variable files:

1. **common.pkrvars.hcl** - Shared variables across all environments
   - HashiCorp tool versions
   - Base VM configuration
   - Security settings

2. **proxmox-host1.pkrvars.hcl** - Host-specific overrides
   - ProxMox connection details
   - Network configuration
   - Storage pool settings
   - Template VM IDs

### Customization

You can customize the build by:

1. **Overriding variables** via command line:
```bash
packer build \
  -var="vm_memory=4096" \
  -var="vm_cores=4" \
  -var="consul_version=1.19.0" \
  ...
```

2. **Creating environment-specific variable files**:
```bash
# packer/variables/proxmox-host2.pkrvars.hcl
proxmox_host = "https://10.0.0.22:8006"
proxmox_node = "pve2"
environment_suffix = "host2"
```

3. **Modifying provisioning scripts**:
   - `scripts/base-setup.sh` - Base system configuration
   - `scripts/install_hashicorp.sh` - HashiCorp tools installation
   - `scripts/security-hardening.sh` - Security configuration

## Provisioning Scripts

### base-setup.sh

Configures the base Ubuntu system:
- Installs essential packages
- Creates HashiCorp directories and users
- Configures kernel parameters
- Sets up systemd-resolved for Consul DNS
- Configures firewall rules
- Enables QEMU guest agent

### install_hashicorp.sh

Installs HashiCorp binaries:
- Downloads Consul, Vault, Nomad from releases.hashicorp.com
- Verifies downloads
- Installs to /usr/local/bin
- Configures systemd services

### security-hardening.sh

Applies security best practices:
- SSH hardening (ciphers, MACs, key exchange)
- Disables password authentication
- Configures fail2ban
- Sets up automatic security updates
- Applies kernel security parameters
- Configures audit logging

## Cloud-init Configuration

### user-data

The autoinstall configuration:
- Sets locale and keyboard layout
- Configures network (DHCP during build)
- Creates packer user with sudo access
- Installs required packages
- Enables SSH and QEMU guest agent

### meta-data

Minimal metadata for cloud-init:
- Instance ID
- Local hostname

## Variables Reference

### Required Variables

These must be set in your .pkrvars.hcl files:

- `proxmox_host` - ProxMox server URL (https://host:8006)
- `proxmox_node` - ProxMox node name
- `proxmox_password` - ProxMox API password (sensitive)
- `storage_pool` - Storage pool name
- `network_cidr` - Network CIDR block
- `gateway_ip` - Default gateway IP
- `base_template_vmid` - VM ID for template

### Optional Variables

These have sensible defaults but can be overridden:

- `vm_name` - Template name (default: ubuntu-hashicorp-template)
- `vm_memory` - RAM in MB (default: 2048, min: 2048)
- `vm_cores` - CPU cores (default: 2)
- `vm_disk_size` - Disk size (default: 20G)
- `network_bridge` - Network bridge (default: vmbr0)
- `dns_servers` - DNS servers (default: [1.1.1.1, 8.8.8.8])
- `vlan_tag` - VLAN tag (default: 0 = no VLAN)
- `ssh_username` - SSH user (default: packer)
- `consul_version` - Consul version (default: 1.18.0)
- `vault_version` - Vault version (default: 1.16.0)
- `nomad_version` - Nomad version (default: 1.7.5)
- `docker_version` - Docker version (default: 24.0.7)

### Security Variables

- `disable_password_auth` - Disable SSH password auth (default: true)
- `disable_root_login` - Disable SSH root login (default: true)
- `enable_ssh_hardening` - Enable SSH hardening (default: true)
- `enable_disk_optimization` - Enable disk optimization (default: true)

## Troubleshooting

### Build Fails During ISO Download

**Problem**: ISO download times out or fails

**Solution**: 
- Check internet connectivity
- Verify ISO URL is accessible
- Increase timeout in template if needed

### SSH Connection Timeout

**Problem**: Packer cannot connect via SSH

**Solution**:
- Verify network configuration in user-data
- Check ProxMox firewall rules
- Increase ssh_timeout variable
- Check VM console for boot errors

### Cloud-init Fails

**Problem**: Cloud-init doesn't complete successfully

**Solution**:
- Check user-data syntax with yamllint
- Verify HTTP server is accessible from VM
- Check VM console for cloud-init errors
- Increase cloud_init_wait_timeout

### Provisioning Script Fails

**Problem**: One of the provisioning scripts fails

**Solution**:
- Check script syntax: `bash -n scripts/script-name.sh`
- Review Packer output for error messages
- Test script manually on a VM
- Check for network issues (downloads)

### Template Not Created

**Problem**: Build completes but template not in ProxMox

**Solution**:
- Verify base_template_vmid is not in use
- Check ProxMox API permissions
- Review ProxMox logs
- Verify storage pool has space

## Resource Requirements

### Minimum (Development)
- 2GB RAM
- 2 CPU cores
- 20GB disk space
- 1 Gbps network

### Recommended (Production)
- 4GB RAM (8GB for Nomad servers)
- 4 CPU cores
- 40GB disk space
- 10 Gbps network

### Build Host Requirements
- 4GB RAM available
- 50GB free disk space (for ISO and temp files)
- Network access to ProxMox API
- Network access to Ubuntu mirrors

## Security Considerations

### During Build
- ProxMox password passed via command line (use environment variable)
- SSH password authentication enabled during build (disabled after)
- HTTP server exposes cloud-init config (only during build)

### After Build
- SSH password authentication disabled
- Root login disabled
- Only SSH key authentication allowed
- Fail2ban configured for brute force protection
- Automatic security updates enabled

### Best Practices
- Use strong ProxMox passwords
- Rotate SSH keys regularly
- Keep HashiCorp tools updated
- Monitor security advisories
- Use separate networks for management

## Next Steps

After building the template:

1. **Test the template** - Deploy a VM from the template
2. **Verify services** - Check Consul, Vault, Nomad are installed
3. **Configure cluster** - Set up HashiCorp cluster configuration
4. **Deploy workloads** - Start using Nomad for orchestration

See the main [TEMPLATE_GUIDE.md](../../../docs/TEMPLATE_GUIDE.md) for use case examples and deployment patterns.

## Related Documentation

- [Template Selection Guide](../../../docs/TEMPLATE_GUIDE.md)
- [Variable Configuration](../../../docs/VARIABLE_CONFIGURATION.md)
- [Build Examples](../../../docs/BUILD_EXAMPLES.md)

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review Packer logs for error messages
3. Consult ProxMox documentation
4. Check HashiCorp tool documentation
