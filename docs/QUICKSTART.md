# Quick Start Guide

> **⚠️ NOTE**: This guide is outdated. For the current production workflow, see the main [README.md](../README.md) and use the Taskfile-based approach.

This guide shows a minimal single-node setup for learning. For production multi-node clusters, use:
- `task bootstrap` - Full automated deployment
- Packer templates for consistent VM images  
- Terraform for infrastructure provisioning
- Ansible for configuration management

---

## Manual Single-Node Setup (Learning Only)

- Proxmox VE host with SSH access
- VM with Ubuntu 24.04 (or create one from template)
- SSH access to the VM
- 2GB RAM, 2 CPU cores minimum

## Step 1: Create Base Template (One Time)

On your Proxmox host:

```bash
cd /root
wget https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img
qm create 8300 --name ubuntu-2404-cloud-template --memory 2048 --cores 2 --net0 virtio,bridge=vmbr0
qm importdisk 8300 ubuntu-24.04-server-cloudimg-amd64.img local-lvm
qm set 8300 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-8300-disk-0
qm set 8300 --boot c --bootdisk scsi0
qm set 8300 --ide2 local-lvm:cloudinit
qm set 8300 --serial0 socket --vga serial0
qm set 8300 --agent enabled=1
qm template 8300
```

## Step 2: Clone and Boot VM

```bash
# Clone template
qm clone 8300 200 --name test-nomad-node --full

# Configure cloud-init
qm set 200 --ipconfig0 ip=10.0.0.170/24,gw=10.0.0.1
qm set 200 --ciuser packer
qm set 200 --cipassword your-password
qm set 200 --sshkeys ~/.ssh/id_rsa.pub

# Start VM
qm start 200
```

Wait 2-3 minutes for cloud-init to complete.

## Step 3: Use Production Approach

**Instead of manual installation, use the automated approach:**

```bash
# From your local machine
git clone <repo-url>
cd hashi_homelab

# Follow main README for:
# 1. Build Packer templates
# 2. Deploy with Terraform  
# 3. Configure with Ansible
# 4. Deploy jobs with Taskfile
```

HashiCorp tools are pre-installed in Packer templates and configured via Ansible.

## Step 4: Configure Services (Automated)

```bash
# Copy configurations
scp configs/consul-standalone.hcl packer@10.0.0.170:/tmp/consul.hcl
scp configs/nomad-dev.hcl packer@10.0.0.170:/tmp/nomad.hcl

# Apply configurations
ssh packer@10.0.0.170 << 'EOF'
sudo mv /tmp/consul.hcl /etc/consul.d/consul.hcl
sudo mv /tmp/nomad.hcl /etc/nomad.d/nomad.hcl
sudo chown consul:consul /etc/consul.d/consul.hcl
sudo chown nomad:nomad /etc/nomad.d/nomad.hcl
EOF
```

## Step 5: Start Services

```bash
ssh packer@10.0.0.170 << 'EOF'
# Start Consul
sudo -u consul nohup consul agent -config-dir=/etc/consul.d/ > /tmp/consul.log 2>&1 &

# Wait for Consul to be ready
sleep 5

# Start Nomad
sudo -u nomad nohup nomad agent -config=/etc/nomad.d/ > /tmp/nomad.log 2>&1 &

# Wait for Nomad to be ready
sleep 5
EOF
```

## Step 6: Verify

```bash
# Check Consul
ssh packer@10.0.0.170 "consul members"

# Check Nomad
ssh packer@10.0.0.170 "nomad node status"
```

Expected output:
```
# Consul
Node            Address          Status  Type    Build   Protocol  DC   Partition  Segment
ubuntu-test-vm  10.0.0.170:8301  alive   server  1.18.0  2         dc1  default    <all>

# Nomad
ID        Node Pool  DC   Name            Class   Drain  Eligibility  Status
b25622d1  default    dc1  ubuntu-test-vm  <none>  false  eligible     ready
```

## Step 7: Access UIs

Open in your browser:
- Consul UI: http://10.0.0.170:8500
- Nomad UI: http://10.0.0.170:4646

## What's Next?

### Run Your First Job

Create a simple job file `example.nomad`:

```hcl
job "example" {
  datacenters = ["dc1"]
  
  group "example" {
    task "hello" {
      driver = "raw_exec"
      
      config {
        command = "/bin/bash"
        args = ["-c", "echo 'Hello from Nomad!' && sleep 30"]
      }
    }
  }
}
```

Run it:
```bash
ssh packer@10.0.0.170 "nomad job run example.nomad"
nomad job status example
```

### Add More Nodes

Repeat steps 2-6 with different VM IDs and IPs to create a cluster.

### Enable Docker

```bash
ssh packer@10.0.0.170 << 'EOF'
# Install Docker
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker nomad
sudo systemctl restart nomad
EOF
```

## Troubleshooting

### Services Won't Start

Check logs:
```bash
ssh packer@10.0.0.170 "tail -50 /tmp/consul.log"
ssh packer@10.0.0.170 "tail -50 /tmp/nomad.log"
```

### Port Already in Use

Kill existing processes:
```bash
ssh packer@10.0.0.170 "sudo pkill -9 consul nomad"
```

Then restart services (Step 5).

### Can't Access UIs

Check firewall:
```bash
ssh packer@10.0.0.170 "sudo ufw status"
```

Ports 8500 and 4646 should be open.

## Full Documentation

- [README.md](README.md) - Complete project overview
- [docs/HASHICORP_INSTALLATION.md](docs/HASHICORP_INSTALLATION.md) - Detailed installation guide
- [docs/TESTING_HASHICORP.md](docs/TESTING_HASHICORP.md) - Testing procedures
- [docs/PROJECT_STATUS.md](docs/PROJECT_STATUS.md) - Current project status

## Support

For issues or questions:
1. Check [docs/PROJECT_STATUS.md](docs/PROJECT_STATUS.md) for known issues
2. Review logs on the VM
3. Consult HashiCorp documentation
4. Open an issue in the repository
