# HashiCorp Homelab with Proxmox

Automated infrastructure-as-code templates for building HashiCorp-powered virtual machines on Proxmox VE using Packer.

> **⚠️ SECURITY NOTICE**: This repository contains infrastructure automation templates. **Never commit your `.env` file or any files containing real credentials to version control.** All sensitive configuration must be stored in your local `.env` file, which is excluded from git via `.gitignore`.

## Features

- 🚀 **Automated VM Template Creation**: Cloud-init based templates for Ubuntu and Alpine Linux
- 🔧 **HashiCorp Stack**: Pre-configured Consul, Nomad, and Vault installations
- 🐳 **Container Ready**: Docker pre-installed for container orchestration
- 🔒 **Security First**: Environment-based configuration with no hardcoded credentials
- 📦 **Packer-based**: Declarative, repeatable infrastructure builds
- 🏠 **Homelab Optimized**: Designed for Proxmox VE homelab environments

## Directory Structure

```plaintext
hashi_homelab/
├── packer-templates/
│   ├── alpine/
│   │   └── alpine.pkr.hcl            # Alpine Linux minimal (Consul only, no Nomad/Docker)
│   └── ubuntu/
│       ├── base-image.pkr.hcl        # Base Ubuntu template with HashiCorp tools
│       └── ubuntu-nomad.pkr.hcl      # Ubuntu with Nomad/Consul/Docker
├── scripts/
│   ├── cloud-init/
│   │   ├── create-ubuntu-template.sh # Create Ubuntu cloud-init base template
│   │   └── create-alpine-template.sh # Create Alpine cloud-init base template
│   └── install_hashicorp.sh          # HashiCorp tools installation script
├── Taskfile.yml                       # Task automation for builds and validation
├── .env.example                       # Environment variable template
├── .env                               # Your local configuration (not in git)
├── .gitignore                         # Excludes secrets and temp files
├── LICENSE                            # License file
└── README.md                          # This file
```

## Prerequisites

### Proxmox Host Requirements

- Proxmox VE 9.x or later
- SSH access to Proxmox host
- Storage configured for VM templates
- Network bridge configured (default: vmbr0)

### Required Tools on Proxmox Host

```bash
# Install libguestfs-tools for cloud image customization
apt-get update
apt-get install -y libguestfs-tools
```

### Local Machine Requirements

- [Packer](https://www.packer.io/downloads) 1.14.x or later
- [Task](https://taskfile.dev/) (optional, but recommended for simplified builds)
- SSH access to Proxmox API
- Network connectivity to Proxmox cluster

Install Task (optional):

```bash
# macOS
brew install go-task

# Linux
sh -c "$(curl --location https://taskfile.dev/install.sh)" -- -d -b ~/.local/bin
```

## Quick Start

### 1. Clone and Configure

```bash
# Clone the repository
git clone <your-repo-url>
cd hashi_homelab

# Create your environment configuration
cp .env.example .env

# Edit .env with your Proxmox settings
nano .env  # or your preferred editor
```

### 2. Configure Environment Variables

Edit `.env` with your specific configuration:

```bash
# Proxmox Configuration
PROXMOX_URL=https://your-proxmox-host:8006/api2/json
PROXMOX_NODE=your-node-name
PROXMOX_USERNAME=root@pam
PROXMOX_PASSWORD=your-proxmox-password

# SSH Configuration
SSH_USERNAME=packer
SSH_PASSWORD=your-ssh-password

# Network Configuration
NETWORK_GATEWAY=192.168.1.1
NETWORK_DNS=192.168.1.1
NETWORK_BRIDGE=vmbr0
NETWORK_VLAN_TAG=

# Storage Configuration
PROXMOX_STORAGE=local-lvm

# Template VM IDs
UBUNTU_BASE_VMID=9000
ALPINE_BASE_VMID=9001
```

### 3. Create Base Cloud-Init Templates

Run these scripts **on your Proxmox host** to create the base cloud-init templates:

```bash
# Copy scripts to Proxmox host
scp scripts/cloud-init/*.sh root@proxmox-host:/root/

# SSH to Proxmox
ssh root@proxmox-host

# Create Ubuntu base template
bash /root/create-ubuntu-template.sh

# Create Alpine base template
bash /root/create-alpine-template.sh
```

These scripts will:

- Download cloud images
- Install qemu-guest-agent
- Configure cloud-init with your credentials
- Create VM templates (VMIDs 9000 and 9001)

### 4. Build Packer Templates

From your local machine, use the Taskfile for simplified builds:

```bash
# Build Ubuntu Nomad template (recommended)
task build:ubuntu

# Build Alpine template (Consul-only, Nomad has issues)
task build:alpine

# Build Ubuntu base image
task build:base

# Validate all templates
task validate

# Format all templates
task fmt
```

The Taskfile automatically loads environment variables from `.env` and sets appropriate `PKR_VAR_clone_vm_id` values for each build.

## Alternative: Manual Packer Commands

If you prefer to run Packer directly:

```bash
# Export environment variables (fish shell users: see troubleshooting)
bash -c 'set -a; source .env; set +a; export PKR_VAR_clone_vm_id=9000; packer build packer-templates/ubuntu/ubuntu-nomad.pkr.hcl'

# Or use task which handles this automatically
```

## Template Descriptions

### Ubuntu Base Template (`base-image.pkr.hcl`)

**Purpose**: Golden Ubuntu template with HashiCorp tools pre-installed

**Includes**:

- Ubuntu 24.04 LTS (Noble)
- Consul v1.18.0
- Nomad v1.7.5
- Vault v1.16.0
- Docker latest
- qemu-guest-agent
- Cloud-init configured

**Use Case**: Base template for general-purpose HashiCorp workloads

### Ubuntu Nomad Template (`ubuntu-nomad.pkr.hcl`)

**Purpose**: Ubuntu template optimized for Nomad worker nodes

**Includes**:

- Ubuntu 24.04 LTS
- Nomad v1.7.5
- Consul v1.18.0
- Docker v28.2.2
- Optimized for container orchestration

**Use Case**: Nomad worker nodes in a HashiCorp cluster

### Alpine Nomad Template (`alpine.pkr.hcl`)

**Purpose**: Lightweight Alpine Linux template (Consul-only for now)

**Includes**:

- Alpine Linux 3.20
- Consul v1.18.0
- Docker (docker.io package)
- Minimal footprint (~1GB memory)

**Known Issues**: Nomad installation currently has issues on Alpine. For now, use this template only for Consul-based workloads or independent VMs.

**Use Case**: Lightweight Consul nodes, minimal VMs, future Nomad support when issues are resolved

## Configuration

### Environment Variables

All configuration is managed through the `.env` file. Key variables:

| Variable | Description | Example |
|----------|-------------|---------|
| `PROXMOX_URL` | Proxmox API endpoint | `https://10.0.0.21:8006/api2/json` |
| `PROXMOX_NODE` | Target Proxmox node | `pve1` |
| `PROXMOX_USERNAME` | Proxmox API user | `root@pam` |
| `PROXMOX_PASSWORD` | Proxmox password | (your password) |
| `SSH_USERNAME` | VM SSH username | `packer` |
| `SSH_PASSWORD` | VM SSH password | (your password) |
| `PROXMOX_STORAGE` | Storage pool name | `NAS-SharedStorage` |
| `UBUNTU_BASE_VMID` | Ubuntu base template ID | `9000` |
| `ALPINE_BASE_VMID` | Alpine base template ID | `9001` |

### HashiCorp Tool Versions

Update versions in `.env`:

```bash
CONSUL_VERSION=1.18.0
NOMAD_VERSION=1.7.5
VAULT_VERSION=1.16.0
```

## Troubleshooting

### Packer SSH Authentication Fails with "unexpected message type 51"

**Problem**: Build fails with error: `ssh: handshake failed: ssh: unexpected message type 51 (expected 60)`

**Root Cause**: Packer automatically loads environment variables with the `PKR_VAR_*` prefix. If your `.env` file contains `SSH_USERNAME=packer`, Packer converts it to `PKR_VAR_ssh_username=packer`, which takes precedence over OS-specific variables like `ALPINE_SSH_USERNAME=alpine`.

**Solution**: The Taskfile explicitly sets `PKR_VAR_ssh_username` to the correct OS-specific value:

```yaml
# For Alpine builds
export PKR_VAR_ssh_username="$ALPINE_SSH_USERNAME"

# For Ubuntu builds  
export PKR_VAR_ssh_username="$UBUNTU_SSH_USERNAME"
```

**Why this matters**:

- Alpine cloud-init creates user `alpine` by default
- Ubuntu cloud-init creates user `packer` (as configured)
- Each template must use the correct username for its OS

**Debug tip**: Run `task debug:packer-vars` to see what variable values Packer is actually using.

### Fish Shell Environment Variable Issues

**Problem**: Fish shell doesn't parse standard `.env` files with `KEY=VALUE` syntax

**Solutions**:

#### Option 1: Use Taskfile (Recommended)

```bash
task build:ubuntu
```

The Taskfile handles environment loading automatically and works with fish shell.

#### Option 2: Use Bash

```bash
bash -c 'set -a; source .env; set +a; export PKR_VAR_clone_vm_id=9000; packer build packer-templates/ubuntu/ubuntu-nomad.pkr.hcl'
```

#### Option 3: Install direnv

```bash
brew install direnv
echo 'direnv hook fish | source' >> ~/.config/fish/config.fish
# Then just cd into the project directory - environment loads automatically
```

### Packer Build Fails with SSH Timeout

**Problem**: `Waiting for SSH to become available...` timeout

**Solution**:

1. Verify qemu-guest-agent is installed in base template
2. Check cloud-init completed: `cloud-init status --wait`
3. Verify SSH password authentication is enabled
4. Check network connectivity to VM

### Environment Variables Not Loaded

**Problem**: Packer uses default values instead of `.env`

**Solution**:

```bash
# Export variables before running Packer
export $(grep -v '^#' .env | xargs)

# Verify variables are set
echo $PROXMOX_URL
```

### Alpine Nomad Template Fails

**Problem**: `/usr/local/bin/nomad: not found` or Nomad binary not executing properly

**Status**: Known issue - Nomad has compatibility issues with Alpine Linux in the current implementation

**Current Status**: The Alpine template successfully installs Consul and Docker, but Nomad installation/execution fails. Use this template for Consul-based workloads only.

**Workaround**: Use Ubuntu Nomad template for any Nomad-based deployments

### Cloud-Init Script Fails

**Problem**: Script can't find `.env` file

**Solution**:

1. Ensure `.env` exists in project root: `hashi_homelab/.env`
2. Run scripts with correct working directory
3. Check file permissions: `chmod +x scripts/cloud-init/*.sh`

## Security Best Practices

1. **Never commit `.env`**: It contains passwords and is git-ignored
2. **Use strong passwords**: Change default passwords immediately
3. **Rotate credentials**: Regularly update API tokens and passwords
4. **Network security**: Restrict Proxmox API access to trusted networks
5. **SSH keys**: Prefer SSH key authentication over passwords for production
6. **Template security**: Review and harden templates before production use

## Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Test changes thoroughly
4. Submit a pull request with clear description
5. Ensure no secrets are committed

## License

MIT License - See LICENSE file for details

## Acknowledgments

- [Proxmox VE](https://www.proxmox.com/)
- [HashiCorp Packer](https://www.packer.io/)
- [HashiCorp Nomad](https://www.nomadproject.io/)
- [HashiCorp Consul](https://www.consul.io/)
- [HashiCorp Vault](https://www.vaultproject.io/)

## Support

For issues and questions:

- Open an issue on GitHub
- Check existing issues for solutions
- Review Proxmox and Packer documentation

---

**Note**: This project is designed for homelab and development environments. For production deployments, additional security hardening and testing is recommended.
