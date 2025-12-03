# Debian Cloud Image Templates

These Packer templates use Debian 12 (Bookworm) cloud images for fast VM creation (~2-3 minutes vs 45 minutes with netinst ISO).

## Prerequisites

### 1. Create Base Cloud Image Template

First, create the base Debian 12 cloud image template in Proxmox:

```bash
# From the repository root
bash packer/scripts/create-debian-cloud-base.sh 10.0.0.8
```

This script will:
- Download the official Debian 12 cloud image (qcow2)
- Create VM 9400 as a template
- Configure cloud-init defaults (user: packer, password: packer)
- Enable QEMU guest agent

### 2. Build Packer Templates

Once the base template exists, build the Nomad templates:

```bash
# Build server template (VM 9402)
source set-proxmox-password.fish
packer build \
  -var-file=packer/variables/common.pkrvars.hcl \
  -var-file=packer/variables/proxmox-host1.pkrvars.hcl \
  packer/templates/debian/debian-nomad-server.pkr.hcl

# Build client template (VM 9401)
packer build \
  -var-file=packer/variables/common.pkrvars.hcl \
  -var-file=packer/variables/proxmox-host1.pkrvars.hcl \
  packer/templates/debian/debian-nomad-client.pkr.hcl
```

## Template IDs

- **9400**: Base Debian 12 cloud image (clone source)
- **9401**: Debian Nomad Client with Docker
- **9402**: Debian Nomad Server with Consul

## How It Works

1. **Base Template (9400)**: Official Debian cloud image with cloud-init pre-configured
2. **Packer Clone**: Uses `proxmox-clone` source to clone from 9400
3. **Provisioning**: Installs Consul, Nomad, Docker, and configures services
4. **Fast Builds**: ~2-3 minutes vs 45 minutes with preseed/netinst

## Cloud Image Details

- **Source**: https://cloud.debian.org/images/cloud/bookworm/latest/
- **Image**: debian-12-generic-amd64.qcow2
- **OS**: Debian 12 (Bookworm)
- **Size**: ~500MB download
- **Cloud-init**: Pre-installed and configured

## Troubleshooting

### SSH Connection Issues

If Packer can't connect via SSH:

1. Check cloud-init is working:
   ```bash
   qm cloudinit dump 9400 user
   ```

2. Verify the VM has network:
   ```bash
   qm guest exec 9400 -- ip addr show
   ```

3. Check cloud-init logs on the VM:
   ```bash
   ssh packer@<vm-ip>
   sudo cloud-init status --long
   sudo journalctl -u cloud-init
   ```

### Base Template Missing

If you see "clone_vm_id 9400 not found":

```bash
# Re-run the setup script
bash packer/scripts/create-debian-cloud-base.sh 10.0.0.8
```

### Slow Builds

If builds are still slow, the base image may not be properly configured. Delete and recreate:

```bash
ssh root@10.0.0.8
qm destroy 9400
exit

bash packer/scripts/create-debian-cloud-base.sh 10.0.0.8
```
