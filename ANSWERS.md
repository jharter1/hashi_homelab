# Answers to Your Questions

Direct answers to the questions you asked.

## 1. How can I rebuild this thing from scratch?

**Full guide:** [docs/REBUILD_FROM_SCRATCH.md](docs/REBUILD_FROM_SCRATCH.md)

**Quick answer:**

```bash
# On Proxmox host - Create base template (one time)
qm create 8300 --name ubuntu-2404-cloud-template --memory 2048 --cores 2
qm importdisk 8300 ubuntu-24.04-server-cloudimg-amd64.img local-lvm
qm set 8300 --scsi0 local-lvm:vm-8300-disk-0
qm set 8300 --ide2 local-lvm:cloudinit
qm set 8300 --agent enabled=1
qm template 8300

# Clone to create VM
qm clone 8300 200 --name test-node --full
qm set 200 --ipconfig0 ip=10.0.0.170/24,gw=10.0.0.1
qm set 200 --ciuser packer --cipassword your-password
qm start 200

# From local machine - Install HashiCorp
scp scripts/install_hashicorp.sh packer@10.0.0.170:/tmp/
ssh packer@10.0.0.170 "sudo /tmp/install_hashicorp.sh"

# Configure
scp configs/consul-standalone.hcl packer@10.0.0.170:/tmp/consul.hcl
scp configs/nomad-dev.hcl packer@10.0.0.170:/tmp/nomad.hcl
ssh packer@10.0.0.170 "sudo mv /tmp/*.hcl /etc/{consul,nomad}.d/ && sudo chown consul:consul /etc/consul.d/consul.hcl && sudo chown nomad:nomad /etc/nomad.d/nomad.hcl"

# Start services
ssh packer@10.0.0.170 "sudo -u consul nohup consul agent -config-dir=/etc/consul.d/ > /tmp/consul.log 2>&1 &"
ssh packer@10.0.0.170 "sudo -u nomad nohup nomad agent -config=/etc/nomad.d/ > /tmp/nomad.log 2>&1 &"

# Verify
ssh packer@10.0.0.170 "consul members && nomad node status"
```

**Time:** 20 minutes first time, 10 minutes after that

---

## 2. What can I get rid of?

**Full guide:** [docs/CLEANUP_GUIDE.md](docs/CLEANUP_GUIDE.md)

### Remove These:

**`.env` file** - Not used anymore
```bash
rm .env
```
We use `.pkrvars.hcl` files instead.

**`downloaded_iso_path/`** - Packer cache
```bash
rm -rf downloaded_iso_path/
```
Packer will re-download if needed.

**Alpine templates** - Not using
```bash
rm -rf packer/templates/alpine/
rm packer/variables/alpine-*.pkrvars.hcl
```

**Old test scripts** - Redundant
```bash
rm packer/test-build-ubuntu.sh
rm packer/validate-ubuntu-*.sh
rm packer/check-storage.fish
rm packer/fix-boot-order.sh
rm scripts/test-vm-200.sh
```

### Keep These:

**Core scripts:**
- `scripts/install_hashicorp.sh`
- `scripts/base-setup.sh`
- `scripts/security-hardening.sh`
- `scripts/configure-nomad-client.sh`

**Packer templates:**
- `packer/templates/ubuntu/ubuntu-base.pkr.hcl`
- `packer/templates/ubuntu/ubuntu-hashicorp.pkr.hcl`

**Configs:**
- `configs/consul-standalone.hcl`
- `configs/nomad-dev.hcl`
- `configs/nomad-client.hcl`

**Documentation:**
- All `docs/*.md` files
- `README.md`
- `QUICKSTART.md`

### Optional:

**`Taskfile.yml`** - Convenience wrapper, not required
- Keep if you like it
- Remove if you prefer direct Packer commands

**`.env.example`** - Keep as reference for what values you need

### Do we use Taskfile?

**No.** It's not part of the current documented workflow.

**Current approach:** Direct Packer commands or bash scripts

**You can remove it** if you want to simplify.

---

## 3. How did we get that first node up purely from code?

**Full explanation:** [docs/HOW_IT_WORKS.md](docs/HOW_IT_WORKS.md)

### The Process:

**Step 1: Base Template (Manual)**
```bash
# On Proxmox - Created VM 8300 as template
qm create 8300 ...
qm template 8300
```
This is infrastructure setup, done once.

**Step 2: Clone VM (Manual)**
```bash
# On Proxmox - Created VM 200 from template
qm clone 8300 200 --full
qm set 200 --ipconfig0 ip=10.0.0.170/24
qm start 200
```
Cloud-init configured networking and SSH.

**Step 3: Install HashiCorp (Automated)**
```bash
# From local machine - Ran installation script
scp scripts/install_hashicorp.sh packer@10.0.0.170:/tmp/
ssh packer@10.0.0.170 "sudo /tmp/install_hashicorp.sh"
```

**What the script did:**
1. Downloaded Consul, Vault, Nomad binaries
2. Installed to `/usr/local/bin/`
3. Created systemd service files
4. Created default configs
5. Set up users and directories

**Step 4: Configure (Automated)**
```bash
# Copied configs
scp configs/consul-standalone.hcl packer@10.0.0.170:/tmp/
scp configs/nomad-dev.hcl packer@10.0.0.170:/tmp/

# Applied configs
ssh packer@10.0.0.170 "sudo mv /tmp/*.hcl /etc/..."
```

**Step 5: Start Services (Manual)**
```bash
ssh packer@10.0.0.170 "sudo -u consul nohup consul agent ..."
ssh packer@10.0.0.170 "sudo -u nomad nohup nomad agent ..."
```

### What's Code vs Manual:

**Manual (Infrastructure):**
- Creating base template
- Cloning VMs
- Setting cloud-init parameters

**Automated (Software):**
- HashiCorp installation
- Configuration deployment
- Service setup

**Future Automation:**
- Packer: Automates "Clone + Install"
- Terraform: Automates "Clone + Install + Configure + Start"

### Why Not Packer for First Node?

**Faster iteration:** SSH is faster than Packer builds

**Easier debugging:** Can see logs in real-time

**Validation:** Prove scripts work before baking into template

**The Packer template does the same thing**, just automated.

---

## 4. What do we need to start integrating Terraform?

**Full guide:** [docs/TERRAFORM_INTEGRATION.md](docs/TERRAFORM_INTEGRATION.md)

### Prerequisites:

✅ **We have:**
- Working base template (VM 8300)
- HashiCorp installation scripts
- Tested configuration (VM 200)
- Proven process

⏳ **We need:**
- Terraform installed locally
- ProxMox provider configured
- Terraform modules written

### What to Add:

**1. Terraform Provider**
```hcl
# terraform/providers.tf
terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "~> 2.9"
    }
  }
}

provider "proxmox" {
  pm_api_url  = "https://10.0.0.21:8006/api2/json"
  pm_user     = "root@pam"
  pm_password = var.proxmox_password
}
```

**2. VM Module**
```hcl
# terraform/modules/nomad-node/main.tf
resource "proxmox_vm_qemu" "node" {
  name   = var.vm_name
  clone  = "ubuntu-2404-cloud-template"
  # ... configuration ...
}

# Install HashiCorp tools
resource "null_resource" "install" {
  provisioner "file" {
    source = "../scripts/install_hashicorp.sh"
    # ...
  }
  provisioner "remote-exec" {
    inline = ["sudo /tmp/install_hashicorp.sh"]
  }
}
```

**3. Main Configuration**
```hcl
# terraform/main.tf
module "consul_servers" {
  source = "./modules/nomad-node"
  count  = 3
  # Creates 3 Consul servers
}

module "nomad_clients" {
  source = "./modules/nomad-node"
  count  = 2
  # Creates 2 Nomad clients
}
```

### What Terraform Does:

**Automates:**
- VM creation from template
- Network configuration
- HashiCorp installation
- Service configuration
- Cluster formation

**Manages:**
- State tracking
- Dependencies
- Lifecycle (create/update/destroy)

### Usage:

```bash
cd terraform
terraform init
terraform plan
terraform apply
# Creates entire cluster

terraform destroy
# Removes everything
```

### Benefits:

1. **Declarative:** Describe what you want
2. **Repeatable:** Same result every time
3. **Scalable:** Change `count = 3` to `count = 10`
4. **Manageable:** Track state, handle updates

### Integration:

**Terraform uses your existing work:**
- ✅ Base template (8300)
- ✅ Installation scripts
- ✅ Configuration files
- ✅ Tested process

**Terraform adds:**
- Automation
- State management
- Cluster orchestration

### Time to Implement:

- **Basic setup:** 4-6 hours
- **Production-ready:** 1-2 days
- **With testing:** 2-3 days

### Recommended Approach:

1. **First:** Complete Packer HashiCorp template
   - Faster VM deployment
   - More reliable

2. **Then:** Add Terraform
   - Use template with tools pre-installed
   - Simpler Terraform config

3. **Finally:** Production hardening
   - TLS configuration
   - ACLs
   - Monitoring

---

## Summary

### 1. Rebuild from scratch
- Create base template (once)
- Clone + install + configure (per VM)
- 20 minutes first time, 10 minutes after

### 2. What to remove
- `.env` (use `.pkrvars.hcl`)
- `downloaded_iso_path/` (cache)
- Alpine templates (not using)
- Old test scripts (redundant)
- Optionally: `Taskfile.yml`

### 3. How we got first node
- Manual: Infrastructure (template, clone)
- Automated: Software (install, configure)
- Manual: Start services
- Future: Packer + Terraform automates all

### 4. Terraform integration
- Need: Provider config, VM module, main config
- Uses: Existing template and scripts
- Adds: Automation, state, orchestration
- Time: 4-6 hours basic, 1-2 days production

---

## Next Steps

**Immediate:**
1. Run cleanup script (remove `.env`, ISOs, etc.)
2. Test rebuild process
3. Document any issues

**Short term:**
1. Complete Packer HashiCorp template
2. Test multi-node manually
3. Start Terraform integration

**Long term:**
1. Production Terraform setup
2. TLS and security
3. Monitoring and logging

See [docs/PROJECT_STATUS.md](docs/PROJECT_STATUS.md) for detailed roadmap.
