# HashiCorp Homelab - AI Coding Agent Instructions

This is a production-ready HashiCorp homelab deploying containerized workloads on Proxmox VE using a Packer → Terraform → Ansible → Nomad workflow.

## Architecture Overview

**Three-Tier Infrastructure Stack:**
1. **Packer** (`packer/templates/debian/`): Builds VM templates with HashiCorp binaries pre-installed (9400→9500→9501 template chain)
2. **Terraform** (`terraform/environments/dev/`): Provisions VMs from templates using `../../modules/nomad-server` and `../../modules/nomad-client` modules
3. **Ansible** (`ansible/playbooks/site.yml`): Configures Docker, Nomad, Consul, NFS mounts, and systemd services via roles
4. **Nomad Jobs** (`jobs/`): Runs containerized services with Traefik ingress and Consul service discovery

**Cluster Topology:**
- 3 Nomad servers (10.0.0.50-52) with co-located Consul for Raft consensus
- 6 Nomad clients (10.0.0.60-65) running Docker workloads, 10 GB RAM each
- NFS storage (10.0.0.100) mounted at `/mnt/nas/` for persistent volumes
- Traefik reverse proxy with automatic Consul catalog integration

**Resource Allocation (as of Feb 2026):**
- Client VMs: 10 GB RAM each (60 GB total), ~75% utilization
- Container memory: ~13.6 GB across 28+ services
- See `docs/RESOURCE_SURVEY.md` for optimization history

**Service Discovery Flow:**
`User → Traefik → Consul → Nomad Task` (tags like `traefik.enable=true` auto-register routes)

## Critical Workflows

### Build & Deploy (via Taskfile)
```bash
task build:debian:base      # Create base cloud template (VM 9400) - 20+ min
task build:debian:server    # Build server template (VM 9500)
task build:debian:client    # Build client template (VM 9501)
task tf:apply               # Deploy 9 VMs with Terraform
task ansible:configure      # Configure all nodes (Docker, Nomad, NFS)
task deploy:all             # Deploy all Nomad jobs (system + services)
task bootstrap              # Run all steps above sequentially
```

### Environment Setup
- **Shell**: Fish shell (NOT bash/zsh) - heredocs don't work, use alternative syntax
- Set `PROXMOX_PASSWORD` via Fish: `set -x PROXMOX_PASSWORD "your-pass"`
- Set `NOMAD_ADDR=http://10.0.0.50:4646` for job deployment
- Packer variables: `packer/variables/proxmox-host1.pkrvars.hcl` (credentials, host, node)
- Terraform variables: `terraform/environments/dev/terraform.tfvars` (IP ranges, cluster size)

### Vault Integration (WIP)
Optional 3-node Vault HA cluster on hub nodes (10.0.0.30-32). See `ansible/TODO.md`, `docs/VAULT_*.md`. Playbooks prefixed with `deploy-hub-*` and `update-nomad-*-vault*` are part of this roadmap.

## Project-Specific Conventions

### Packer Templates (Layered Build Strategy)
- **VM 9400**: Base Debian 12 cloud image (minimal, cloud-init only)
- **VM 9500**: Server template (Consul + Nomad server binaries)
- **VM 9501**: Client template (Consul + Nomad client + Docker)
- Templates clone from each other for incremental builds
- All use cloud-init with `ubuntu` user and SSH keys
- Variables split: `common.pkrvars.hcl` + `proxmox-host1.pkrvars.hcl`

### Terraform Modules
- Modules in `terraform/modules/nomad-{server,client}/` create VMs using `bpg/proxmox` provider
- Pass `template_ids` array and `proxmox_nodes` for HA distribution
- Modules do NOT configure services (that's Ansible's job)
- Client module removed `depends_on` to enable parallel creation with servers

### Ansible Patterns
- **Roles are idempotent**: Use `template:` or `copy:` with `notify: restart <service>`
- **Jinja2 templates**: `.j2` files in `roles/*/templates/` (e.g., `nomad-client.hcl.j2`)
- **Systemd services**: Created via `copy:` task, started/enabled separately
- **NFS mounts**: Configured in `base-system` role, clients only
- **Host volumes**: Directories created at `/mnt/nas/<volume_name>` for Nomad jobs

### Nomad Job Files (.nomad.hcl)
- **System jobs** (`jobs/system/`): Traefik, Grafana Alloy (run on all/most clients)
- **Services** (`jobs/services/`): Apps with persistent data via host volumes
- **Volume pattern**: Declare `volume "name" { type = "host"; source = "name" }` in group, mount in task
- **Network mode**: Use `network { mode = "host" }` for services needing static ports
- **Traefik tags**: Add to `service` block: `tags = ["traefik.enable=true", "traefik.http.routers.X.rule=Host(...)"]`
- **Template blocks**: Embedded configs via `template { destination = "local/config.yml"; data = <<EOH ... EOH }`

### Storage Architecture
- All persistent data lives on NFS at `/mnt/nas/<volume_name>/`
- Ansible creates volume directories during client configuration
- Host volumes defined in Nomad client config at `/etc/nomad.d/nomad.hcl`
- Services reference volumes by name (e.g., `postgres_data`, `grafana_data`)

### Fish Scripts (scripts/*.fish)
- **Primary shell is Fish** - all scripts use Fish syntax, NOT bash
- Use `set -x` for environment variables (not `export`)
- Source `set-proxmox-password.fish` for credentials
- Example: `setup-vault.fish` orchestrates Ansible + Terraform for Vault setup
- **Heredocs don't work in Fish** - use alternative patterns like `echo "..." | command` or temp files

## Key Files & Directories

- [Taskfile.yml](../Taskfile.yml): Primary automation interface (build, deploy, bootstrap)
- [README.md](../README.md): Architecture diagrams, quick start, service access
- [ansible/playbooks/site.yml](../ansible/playbooks/site.yml): Master playbook applying all roles
- [jobs/services/prometheus.nomad.hcl](../jobs/services/prometheus.nomad.hcl): Reference for Consul SD config and volume usage
- [terraform/environments/dev/main.tf](../terraform/environments/dev/main.tf): Shows module usage pattern
- [docs/TROUBLESHOOTING.md](../docs/TROUBLESHOOTING.md): Common issues, gotchas, and solutions (Vault integration, networking, database, etc.)
- [docs/NEW_SERVICES_DEPLOYMENT.md](../docs/NEW_SERVICES_DEPLOYMENT.md): Architecture and service deployment patterns
- [docs/INFRASTRUCTURE.md](../docs/INFRASTRUCTURE.md): Storage architecture and migration history

## Common Tasks

**Adding a new service:**
1. Create `jobs/services/<name>.nomad.hcl` with host volume + Traefik tags
2. Add volume directory to Ansible `base-system` role if not using existing volume
3. Deploy: `nomad job run jobs/services/<name>.nomad.hcl`

**Updating Nomad/Consul versions:**
1. Edit `packer/variables/common.pkrvars.hcl` (version variables)
2. Rebuild templates: `task build:debian:server` and `task build:debian:client`
3. Destroy/recreate VMs: `task tf:destroy && task tf:apply`
4. Reconfigure: `task ansible:configure`

**Debugging job failures:**
- Check Nomad UI: `http://10.0.0.50:4646`
- SSH to client: `ssh ubuntu@10.0.0.60` and `nomad alloc logs -stderr <alloc-id>`
- Check Consul: `consul catalog services`
- See `docs/TROUBLESHOOTING.md` for common issues and solutions

**Working with Vault:**
- **ALWAYS** run `source .credentials` before Vault commands to load token
- Check secrets: `source .credentials; vault kv get secret/path/to/secret`
- List secrets: `source .credentials; vault kv list secret/postgres`

**Using the Nomad MCP Server:**
- Build: `task mcp:build:nomad`
- Test: `cd mcp-servers/nomad && node test-connection.mjs`
- Query jobs, allocations, and logs through AI assistants
- See `mcp-servers/nomad/QUICKSTART.md` for setup

**Working with Packer:**
- Base template creation requires DNS on Proxmox for Debian cloud image download
- Templates are immutable - destroy and rebuild rather than modify
- Use `task validate` to check all template syntax

## Avoiding Common Pitfalls

> **📖 See troubleshooting sections in:**
> - `docs/NEW_SERVICES_DEPLOYMENT.md` - Service deployment issues & gotchas
> - `docs/POSTGRESQL.md` - Database management and anti-patterns
> - `docs/AUTHELIA.md` - SSO and authentication issues

- **Don't** manually edit Nomad/Consul configs on VMs - use Ansible roles with templates
- **Don't** run `nomad agent` directly - systemd manages services
- **Don't** create volumes on client filesystems - all data goes to `/mnt/nas/`
- **Don't** use bridge networking unless necessary - host mode simplifies port management (CNI plugins not installed)
- **Don't** skip the template build chain (9400→9500→9501) - each layer depends on the previous
- **Don't** use bash heredoc syntax (<<EOF) - Fish shell doesn't support it
- **Don't** use `export` for env vars - Fish uses `set -x`
- **Don't** forget `vault {}` blocks when using Vault templates (required in EVERY task, including sidecars)
- **Don't** manually create PostgreSQL databases - use automated init-databases system
- **Don't** hardcode IP addresses in homepage widgets - services move nodes when redeployed
- **Don't** forget leading dot in Authelia cookie domain - `.lab.hartr.net` not `lab.hartr.net`
- **Don't** use interactive Docker exec over SSH - use `--name='...' --email='...'` flags instead
- **Do** use static ports with host networking to avoid port conflicts
- **Do** use `task bootstrap:check` before full bootstrap to verify prerequisites
- **Do** set `PROXMOX_PASSWORD` before Packer builds
- **Do** wait 60s after Terraform apply for VMs to boot before running Ansible
- **Do** update all dependent services after moving PostgreSQL or changing database connectivity
- **Do** verify container IDs before exec - `docker ps` to get current ID
- **Do** check init-databases logs after PostgreSQL deployment
## Resource Management & Operations

**Checking Cluster Resources (Fish shell):**
```fish
# Check Nomad client memory
for node_name in dev-nomad-client-1 dev-nomad-client-2 dev-nomad-client-3 dev-nomad-client-4 dev-nomad-client-5 dev-nomad-client-6
  set node_id (curl -s http://10.0.0.50:4646/v1/nodes | python3 -c "import sys, json; nodes = json.load(sys.stdin); print([n['ID'] for n in nodes if '$node_name' == n['Name']][0])")
  curl -s http://10.0.0.50:4646/v1/node/$node_id | python3 -c "import sys, json; n = json.load(sys.stdin); mem = n.get('NodeResources', {}).get('Memory', {}).get('MemoryMB', 0); print('$node_name: ' + str(mem) + ' MB')"
end

# Check actual VM memory
for ip in 10.0.0.60 10.0.0.61 10.0.0.62 10.0.0.63 10.0.0.64 10.0.0.65
  ssh ubuntu@$ip "free -h | grep Mem"
end

# Check all job statuses
curl -s http://10.0.0.50:4646/v1/jobs | python3 -c "import sys, json; [print(f\"{j['Name']}: {j['Status']}\") for j in json.load(sys.stdin)]"
```

**Increasing Client Memory:**
1. Edit `terraform/environments/dev/terraform.tfvars`: `nomad_client_memory = 10240`
2. Apply: `task tf:apply`
3. **CRITICAL**: Memory changes require cold boot, not just reboot
4. Stop clients: `ssh ubuntu@10.0.0.60 "sudo shutdown -h now"` (repeat for 61-65)
5. Start VMs from Proxmox UI
6. Verify: `ssh ubuntu@10.0.0.60 "free -h"`

**Handling Services After Reboots:**
- Services may show "dead" status after client reboots
- Restart: `nomad job run -address=http://10.0.0.50:4646 jobs/services/<name>.nomad.hcl`
- Restart all: `for job in jobs/services/*.nomad.hcl; nomad job run -address=http://10.0.0.50:4646 $job; end`

**Service Memory Tuning:**
- Edit job files in `jobs/services/*.nomad.hcl`
- Update `resources { memory = 256 }` block
- Redeploy with `nomad job run`
- Monitor for OOM kills over 48-72 hours
- See `docs/RESOURCE_SURVEY.md` for optimization guidelines