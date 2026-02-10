# MCP Servers Quick Reference

> **Important:** This file describes the **legacy local TypeScript MCP servers** under `mcp-servers/`.  
> For new setups, use the **Recommended Modern MCP Configuration** below (community `mcp-nomad` + generic filesystem/shell/http servers) and treat the per-service Node servers as deprecated.

## Recommended Modern MCP Configuration

### Nomad (Go-based `mcp-nomad`)

Install `mcp-nomad` using any of the options from its README (CLI, Docker, or `npx`). A simple Claude/Cursor config using `npx`:

```json
{
  "mcpServers": {
    "mcp_nomad": {
      "command": "npx",
      "args": [
        "-y",
        "@kocierik/mcp-nomad@latest"
      ],
      "env": {
        "NOMAD_ADDR": "http://10.0.0.50:4646",
        "NOMAD_TOKEN": "your-acl-token-if-needed"
      }
    }
  }
}
```

Or, if you install the CLI globally:

```bash
npm install -g @kocierik/mcp-nomad
```

```json
{
  "mcpServers": {
    "mcp_nomad": {
      "command": "mcp-nomad",
      "args": [],
      "env": {
        "NOMAD_ADDR": "http://10.0.0.50:4646",
        "NOMAD_TOKEN": "your-acl-token-if-needed"
      }
    }
  }
}
```

### Terraform (official HashiCorp Terraform MCP server)

Use the official Terraform MCP server published by HashiCorp. For Cursor/Claude using Docker:

```json
{
  "mcpServers": {
    "terraform": {
      "command": "docker",
      "args": [
        "run",
        "-i",
        "--rm",
        "-e", "TFE_ADDRESS=<>",
        "-e", "TFE_TOKEN=<>",
        "hashicorp/terraform-mcp-server:0.4.0"
      ]
    }
  }
}
```

See `https://developer.hashicorp.com/terraform/mcp-server` for up-to-date usage, available tools, and version numbers.

### Filesystem / Shell / HTTP MCP Servers

Use community filesystem, shell, and HTTP MCP servers to give agents rich access to your homelab:

- **Filesystem**: root the server at `/Users/jackharter/Developer/hashi_homelab` so agents can read `terraform/`, `ansible/`, `jobs/`, `docs/`, etc.
- **Shell**: working directory `/Users/jackharter/Developer/hashi_homelab` so agents can run `nomad`, `consul`, `vault`, `terraform`, `ansible`, `task`, etc.
- **HTTP**: used to send requests to:
  - `NOMAD_ADDR` (e.g., `http://10.0.0.50:4646`)
  - `CONSUL_ADDR` (e.g., `http://10.0.0.50:8500`)
  - `VAULT_ADDR` (e.g., `http://10.0.0.30:8200`)
  - `PROMETHEUS_ADDR` (e.g., `http://10.0.0.60:9090`)
  - Proxmox API, Traefik API, and any other HTTP endpoints in your lab.

A conceptual combined configuration:

```json
{
  "mcpServers": {
    "homelab_fs": {
      "command": "your-filesystem-mcp-binary",
      "args": [],
      "env": {
        "ROOT": "/Users/jackharter/Developer/hashi_homelab"
      }
    },
    "homelab_shell": {
      "command": "your-shell-mcp-binary",
      "args": [],
      "env": {
        "WORKDIR": "/Users/jackharter/Developer/hashi_homelab"
      }
    },
    "homelab_http": {
      "command": "your-http-mcp-binary",
      "args": []
    },
    "mcp_nomad": {
      "command": "mcp-nomad",
      "args": [],
      "env": {
        "NOMAD_ADDR": "http://10.0.0.50:4646",
        "NOMAD_TOKEN": "your-acl-token-if-needed"
      }
    }
  }
}
```

> **Note:** Replace `your-*-mcp-binary` with the actual binaries/scripts for the filesystem, shell, and HTTP MCP servers you install.

### Example Queries with Modern Stack

- **Nomad-focused:**
  - "List all jobs and show which ones are failing."
  - "Get logs for the `prometheus` job on the most recent failed allocation."
- **Cross-tool:**
  - "Show me the `jobs/services/prometheus.nomad.hcl` job file and compare it to the running job state."
  - "Run `terraform plan` for the dev environment and summarize any changes that affect Nomad clients."
  - "Call the Traefik API and tell me which routers are fronting the Grafana service."

---

## Legacy Local MCP Servers (Deprecated)

The sections below document the original per-service Node/TypeScript MCP servers. They still work but are **not recommended for new usage**; prefer the modern configuration above.

### Nomad MCP Server (legacy)

**Tools:** 8 tools for job and cluster management

```json
{
  "nomad": {
    "command": "node",
    "args": ["/Users/jackharter/Developer/hashi_homelab/mcp-servers/nomad/dist/index.js"],
    "env": {
      "NOMAD_ADDR": "http://10.0.0.50:4646"
    }
  }
}
```

**Usage:**
- "What jobs are running?"
- "Show me grafana job status"
- "Get logs from allocation abc123"

---

### Consul MCP Server (legacy)

**Tools:** 7 tools for service discovery and KV store

```json
{
  "consul": {
    "command": "node",
    "args": ["/Users/jackharter/Developer/hashi_homelab/mcp-servers/consul/dist/index.js"],
    "env": {
      "CONSUL_ADDR": "http://10.0.0.50:8500"
    }
  }
}
```

**Usage:**
- "List all services in Consul"
- "Get health of traefik service"
- "Read KV key config/myapp"
- "Who is the Consul leader?"

---

### Vault MCP Server (legacy)

**Tools:** 7 tools for secrets management

```json
{
  "vault": {
    "command": "node",
    "args": ["/Users/jackharter/Developer/hashi_homelab/mcp-servers/vault/dist/index.js"],
    "env": {
      "VAULT_ADDR": "http://10.0.0.30:8200",
      "VAULT_TOKEN": "your-vault-token"
    }
  }
}
```

**Usage:**
- "Is Vault sealed?"
- "List secrets under secret/metadata/"
- "Read secret/data/postgres/creds"
- "What policies do I have?"

---

### Terraform MCP Server (legacy)

**Tools:** 6 tools for infrastructure inspection

```json
{
  "terraform": {
    "command": "node",
    "args": ["/Users/jackharter/Developer/hashi_homelab/mcp-servers/terraform/dist/index.js"],
    "env": {
      "TERRAFORM_DIR": "/Users/jackharter/Developer/hashi_homelab/terraform"
    }
  }
}
```

**Usage:**
- "Validate dev environment terraform"
- "What resources are in terraform state?"
- "Show terraform outputs for dev"
- "Check if terraform files are formatted"

---

### Ansible MCP Server (legacy)

**Tools:** 7 tools for automation inspection

```json
{
  "ansible": {
    "command": "node",
    "args": ["/Users/jackharter/Developer/hashi_homelab/mcp-servers/ansible/dist/index.js"],
    "env": {
      "ANSIBLE_DIR": "/Users/jackharter/Developer/hashi_homelab/ansible"
    }
  }
}
```

**Usage:**
- "List all ansible playbooks"
- "Show me the site.yml playbook"
- "Ping all nomad clients"
- "What roles are available?"

---

### Proxmox MCP Server (legacy)

**Tools:** 7 tools for virtualization management

```json
{
  "proxmox": {
    "command": "node",
    "args": ["/Users/jackharter/Developer/hashi_homelab/mcp-servers/proxmox/dist/index.js"],
    "env": {
      "PROXMOX_HOST": "https://10.0.0.21:8006",
      "PROXMOX_USER": "root@pam",
      "PROXMOX_PASSWORD": "your-password"
    }
  }
}
```

**Usage:**
- "List all VMs in the cluster"
- "What's the status of VM 100?"
- "Show storage usage"
- "How healthy are the proxmox nodes?"

---

### Traefik MCP Server (legacy)

**Tools:** 8 tools for reverse proxy and ingress management

```json
{
  "traefik": {
    "command": "node",
    "args": ["/Users/jackharter/Developer/hashi_homelab/mcp-servers/traefik/dist/index.js"],
    "env": {
      "TRAEFIK_API": "http://10.0.0.60:8080"
    }
  }
}
```

**Usage:**
- "List all Traefik routers"
- "Show details for grafana router"
- "What services are registered?"
- "List all middleware configurations"

---

### Prometheus MCP Server (legacy)

**Tools:** 10 tools for metrics and resource monitoring

```json
{
  "prometheus": {
    "command": "node",
    "args": ["/Users/jackharter/Developer/hashi_homelab/mcp-servers/prometheus/dist/index.js"],
    "env": {
      "PROMETHEUS_ADDR": "http://10.0.0.60:9090"
    }
  }
}
```

**Usage:**
- "Show me top 10 containers by memory usage"
- "What's the memory usage across all VMs?"
- "Give me a complete resource summary"
- "Which containers are using the most CPU?"
- "Show disk usage on /mnt/nas"

## Task Commands

```bash
# Build all servers
task mcp:build:all

# Build individual servers
task mcp:build:nomad
task mcp:build:consul
task mcp:build:vault
task mcp:build:terraform
task mcp:build:ansible
task mcp:build:proxmox
task mcp:build:traefik

# Development mode (Nomad example)
task mcp:dev:nomad

# Test with inspector (Nomad example)
task mcp:test:nomad
```

## Tool Count Summary

- **Nomad:** 8 tools
- **Consul:** 7 tools
- **Vault:** 7 tools
- **Terraform:** 6 tools
- **Ansible:** 7 tools
- **Proxmox:** 7 tools
- **Traefik:** 8 tools
- **Total:** 50 tools for managing your homelab!

## Example Queries

### Cross-Service Queries

"Check if all my infrastructure is healthy" → Queries Nomad, Consul, Vault, Proxmox

"What's using the most resources?" → Queries Proxmox VMs and Nomad allocations

"Are my secrets properly configured?" → Checks Vault + Nomad integration

### Troubleshooting

"Why is the grafana service down?" → Checks Nomad job, Consul service, Proxmox VM

"Show me recent changes to infrastructure" → Checks Terraform state, Ansible playbooks

### Automation

"Deploy the monitoring stack" → Uses Terraform to check state, Nomad to deploy

"Update all client configurations" → Uses Ansible to show playbook, run dry-run

## Security Notes

⚠️ **Tokens and Passwords:**
- Store sensitive values in environment variables
- Use read-only tokens when possible
- Never commit credentials to version control

⚠️ **Proxmox Authentication:**
- Option 1: Use API tokens (recommended)
- Option 2: Use username/password (shown above)

⚠️ **Vault Access:**
- Requires valid VAULT_TOKEN with appropriate policies
- Some tools are read-only, others require write permissions
