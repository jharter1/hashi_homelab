# MCP Servers Quick Reference

## Build All Servers

```bash
task mcp:build:all
```

Builds all 8 MCP servers with 60 total tools.

## Individual Server Configuration

### Nomad MCP Server

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

### Consul MCP Server

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

### Vault MCP Server

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

### Terraform MCP Server

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

### Ansible MCP Server

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

### Proxmox MCP Server

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

### Traefik MCP Server

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

### Prometheus MCP Server

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

---

## Complete MCP Configuration

Add all servers to your MCP settings file:

```json
{
  "mcpServers": {
    "nomad": {
      "command": "node",
      "args": ["/Users/jackharter/Developer/hashi_homelab/mcp-servers/nomad/dist/index.js"],
      "env": { "NOMAD_ADDR": "http://10.0.0.50:4646" }
    },
    "consul": {
      "command": "node",
      "args": ["/Users/jackharter/Developer/hashi_homelab/mcp-servers/consul/dist/index.js"],
      "env": { "CONSUL_ADDR": "http://10.0.0.50:8500" }
    },
    "vault": {
      "command": "node",
      "args": ["/Users/jackharter/Developer/hashi_homelab/mcp-servers/vault/dist/index.js"],
      "env": {
        "VAULT_ADDR": "http://10.0.0.30:8200",
        "VAULT_TOKEN": "your-token"
      }
    },
    "terraform": {
      "command": "node",
      "args": ["/Users/jackharter/Developer/hashi_homelab/mcp-servers/terraform/dist/index.js"],
      "env": { "TERRAFORM_DIR": "/Users/jackharter/Developer/hashi_homelab/terraform" }
    },
    "ansible": {
      "command": "node",
      "args": ["/Users/jackharter/Developer/hashi_homelab/mcp-servers/ansible/dist/index.js"],
      "env": { "ANSIBLE_DIR": "/Users/jackharter/Developer/hashi_homelab/ansible" }
    },
    "proxmox": {
      "command": "node",
      "args": ["/Users/jackharter/Developer/hashi_homelab/mcp-servers/proxmox/dist/index.js"],
      "env": {
        "PROXMOX_HOST": "https://10.0.0.21:8006",
        "PROXMOX_USER": "root@pam",
        "PROXMOX_PASSWORD": "your-password"
      }
    },
    "traefik": {
      "command": "node",
      "args": ["/Users/jackharter/Developer/hashi_homelab/mcp-servers/traefik/dist/index.js"],
      "env": {
        "TRAEFIK_API": "http://10.0.0.60:8080"
      }
    },
    "prometheus": {
      "command": "node",
      "args": ["/Users/jackharter/Developer/hashi_homelab/mcp-servers/prometheus/dist/index.js"],
      "env": {
        "PROMETHEUS_ADDR": "http://10.0.0.60:9090"
      }
    }
  }
}
```

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
