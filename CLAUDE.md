# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Architecture Overview

This is a full-stack homelab IaC project following a strict four-tier pipeline:

```
Packer → Terraform → Ansible → Nomad Jobs
```

1. **Packer** (`packer/templates/debian/`): Builds a layered chain of VM templates (9400 base → 9500 server → 9501 client). Each layer depends on the previous.
2. **Terraform** (`terraform/environments/dev/`): Provisions VMs from templates using `../../modules/nomad-server` and `../../modules/nomad-client` (via `bpg/proxmox` provider).
3. **Ansible** (`ansible/playbooks/`): Configures Docker, Nomad/Consul services, NFS mounts, and host volumes via idempotent roles.
4. **Nomad Jobs** (`jobs/`): Runs containerized services with Traefik ingress and Consul service discovery.

**Cluster IPs:**
- Nomad servers: `10.0.0.50-52` (Consul co-located)
- Nomad clients: `10.0.0.60-65` (Docker workloads, 6 GB RAM each)
- NFS storage: `10.0.0.100`, mounted at `/mnt/nas/` on all clients
- Vault hub cluster (optional): `10.0.0.30-32`
- Consul/DNS: `10.0.0.10`

**Service routing:** `User → Traefik → Consul catalog → Nomad task`
Traefik auto-discovers services via tags like `traefik.enable=true` on Consul service registrations.

## Key Commands

```bash
# Infrastructure lifecycle
task build:debian:base      # Create base cloud template (VM 9400) on Proxmox
task build:debian:server    # Build Nomad server template (VM 9500)
task build:debian:client    # Build Nomad client template (VM 9501)
task tf:apply               # Provision 9 VMs with Terraform
task ansible:configure      # Configure all nodes (Docker, Nomad, Consul, NFS)
task deploy:all             # Deploy all Nomad jobs (system + services)
task bootstrap              # Run all steps above sequentially
task bootstrap:check        # Validate prerequisites without executing

# Targeted Ansible operations
task ansible:install:binaries        # Install/upgrade HashiCorp binaries (slow)
task ansible:configure:base          # DNS, packages, NFS, volumes only (fast)
task ansible:configure:services      # Consul and Nomad service configs
task ansible:update:configs          # Update configs and restart if changed
task ansible:restart                 # Quick restart Consul/Nomad on all nodes
task ansible:restart:consul          # Restart Consul only
task ansible:restart:nomad           # Restart Nomad only

# Validate and format
task validate               # Validate all Packer templates
task fmt                    # Format all Packer templates with packer fmt

# MCP server development
task mcp:build:all          # Build all 8 MCP servers (npm install + build)
task mcp:build:<name>       # Build individual MCP server (nomad/consul/vault/etc.)
task mcp:dev:nomad          # Run Nomad MCP server in dev mode

# Nomad job operations (set NOMAD_ADDR first)
export NOMAD_ADDR=http://10.0.0.50:4646  # bash/zsh
set -x NOMAD_ADDR http://10.0.0.50:4646  # fish
nomad job validate jobs/services/<category>/<name>/<name>.nomad.hcl
nomad job run jobs/services/<category>/<name>/<name>.nomad.hcl
nomad job status <name>
nomad alloc logs -stderr <alloc-id>
```

## Shell Environment

**Primary shell is Fish** — all scripts use Fish syntax. This is critical:
- Use `set -x VAR value` (NOT `export VAR=value`)
- Heredocs (`<<EOF`) do NOT work in Fish — use alternative patterns (echo pipes, temp files)
- Set Proxmox password: `fish -c "source scripts/set-proxmox-password.fish && packer build ..."`
- Scripts in `scripts/*.fish` are Fish-only

## Nomad Job Conventions

All production services use **host network mode** (CNI plugins not installed):

```hcl
network {
  mode = "host"
  port "http" { static = 3000 }  # always static ports
}
config {
  network_mode = "host"
  dns_servers  = ["10.0.0.10", "1.1.1.1"]  # Consul DNS + fallback
}
```

**Three service patterns** (see `jobs/services/_patterns/README.md`):
1. **PostgreSQL-backed** (`grafana`, `gitea`, `vaultwarden`, etc.): Uses Vault workload identity for DB creds, `vault {}` block required in EVERY task including sidecars
2. **Host volume only** (`prometheus`, `loki`, `minio`): Self-contained with embedded config via `template` blocks
3. **Multi-container** (`freshrss`): Multiple tasks sharing a network namespace

**Standard Traefik tags** for production services:
```hcl
tags = [
  "traefik.enable=true",
  "traefik.http.routers.SERVICE.rule=Host(`SERVICE.lab.hartr.net`)",
  "traefik.http.routers.SERVICE.entrypoints=websecure",
  "traefik.http.routers.SERVICE.tls=true",
  "traefik.http.routers.SERVICE.tls.certresolver=letsencrypt",
  "traefik.http.routers.SERVICE.middlewares=authelia@file",
]
```

**Vault secret injection pattern:**
```hcl
vault {}  # in task block

template {
  destination = "secrets/db.env"
  env         = true
  data        = <<EOH
DB_PASSWORD={{ with secret "secret/data/postgres/SERVICE" }}{{ .Data.data.password }}{{ end }}
DB_HOST={{ range service "postgresql" }}{{ .Address }}{{ end }}:5432
EOH
}
```

## Storage Architecture

All persistent data lives on NFS. Never create volumes on local client filesystems.

- Data path: `/mnt/nas/<volume_name>/`
- Ansible `base-system` role creates volume directories and defines host volumes in `/etc/nomad.d/nomad.hcl`
- Volume name in job file must match host volume definition in Nomad client config
- When adding a new service with a new volume: add directory creation to `ansible/roles/base-system/tasks/main.yml`

## Adding a New Service

1. Create `jobs/services/<category>/<service-name>/<service-name>.nomad.hcl`
2. Choose pattern from `jobs/services/_patterns/README.md`
3. If new volume needed: add to `ansible/roles/base-system/tasks/main.yml`
4. Check `docs/CHEATSHEET.md` for already-allocated static ports
5. Create Vault secrets if needed: use `scripts/setup-*.fish` patterns
6. Validate before deploying: `nomad job validate <file>`
7. Add to `Taskfile.yml` `deploy:services` task

## Ansible Patterns

- Roles are in `ansible/roles/` — use `template:` with `notify: restart <service>` for config changes
- Jinja2 templates: `roles/*/templates/*.j2`
- `site.yml` is the master playbook; targeted playbooks exist for fast operations
- Use `--limit nomad_servers` or `--limit nomad_clients` for targeted runs

## Packer Template Chain

Templates must be built in order — each clones from the previous:
- `9400`: Base Debian 12 cloud image (requires DNS on Proxmox host for initial creation)
- `9500`: Nomad server (Consul + Nomad server binaries from 9400)
- `9501`: Nomad client (Consul + Nomad client + Docker from 9400)

Variables: `packer/variables/common.pkrvars.hcl` (versions) + `packer/variables/proxmox-host1.pkrvars.hcl` (host config).

## MCP Servers

8 Node.js MCP servers in `mcp-servers/` providing AI tool access to: Nomad, Consul, Vault, Terraform, Ansible, Proxmox, Traefik, Prometheus. Each follows `npm install && npm run build` → `dist/index.js`. See `mcp-servers/MCP_QUICK_REFERENCE.md` for the 50 available tools.

## Common Pitfalls

- **Don't** manually edit Nomad/Consul configs on VMs — use Ansible roles
- **Don't** use bridge networking — host mode only (CNI not installed)
- **Don't** skip the Packer template build chain (9400→9500→9501)
- **Don't** use bash heredoc syntax in Fish scripts
- **Don't** use `export` in Fish — use `set -x`
- **Don't** forget `vault {}` block in every task that uses Vault templates (including sidecars)
- **Don't** hardcode IP addresses in homepage widgets (services move nodes on redeploy)
- **Don't** use leading dot omission for Authelia cookie domain — must be `.lab.hartr.net`
- **Do** run `task bootstrap:check` before full bootstrap
- **Do** wait 60s after `terraform apply` before running Ansible
- **Do** use `nomad job validate` before `nomad job run`
- **Memory changes** require cold boot (shutdown + start from Proxmox), not just reboot

## Key Reference Files

- `docs/TROUBLESHOOTING.md` — Common failures: Vault integration, networking, database, service-specific gotchas
- `docs/NEW_SERVICES_DEPLOYMENT.md` — Service architecture and deployment patterns
- `docs/INFRASTRUCTURE.md` — Storage architecture and NFS migration history
- `docs/CHEATSHEET.md` — Port allocations and command shortcuts
- `jobs/services/_patterns/README.md` — Canonical patterns for all three service types
- `ansible/TODO.md` — Vault-Nomad integration roadmap (Phase 2-4)
