# MCP Servers for Hashi Homelab

> **Status: Deprecated local implementations**
>
> This directory contains **legacy, project-specific MCP servers** that were generated to talk to your HashiCorp homelab. They are no longer the recommended way to connect AI agents to your infrastructure.
>
> For ongoing use, prefer:
> - **Community Nomad MCP server**: Go-based `mcp-nomad` (`@kocierik/mcp-nomad`) for Nomad
> - **Official Terraform MCP server**: HashiCorp’s `terraform-mcp-server` (`hashicorp/terraform-mcp-server` Docker image / binary)
> - **Generic filesystem/shell/HTTP MCP servers**: For reading this repo, running CLIs (`nomad`, `terraform`, `ansible`, `vault`, `consul`), and calling HTTP APIs (Proxmox, Traefik, Prometheus, etc.)
>
> The code here is kept as a reference and can be safely deleted once you are fully migrated.

## Legacy Local Servers

### Nomad MCP Server
Location: `nomad/`

Interact with your Nomad cluster:
- List and manage jobs
- View allocation status and logs
- Monitor cluster health
- Stop/start jobs programmatically

[Read the Nomad MCP docs →](nomad/README.md)

### Consul MCP Server
Location: `consul/`

Service discovery and KV store management:
- Query service catalog
- Read/write KV store
- Check service health
- Monitor cluster members

### Vault MCP Server
Location: `vault/`

Secrets management (requires appropriate permissions):
- Read secrets from KV store
- Check policy assignments
- Monitor seal status
- Token management

### Terraform MCP Server
Location: `terraform/`

Infrastructure validation and inspection:
- Validate configurations
- Run terraform plan
- Show state
- List resources

### Ansible MCP Server
Location: `ansible/`

Automation and configuration inspection:
- List playbooks and roles
- Check inventory
- Dry-run playbooks
- Test connectivity

### Proxmox MCP Server
Location: `proxmox/`

Virtualization platform management:
- Query VM status
- List cluster resources
- Monitor node health
- Check storage

### Traefik MCP Server
Location: `traefik/`

Reverse proxy and ingress management:
- List HTTP/TCP routers
- View service backends
- Check middleware configuration
- Monitor entrypoints

## Quick Start

## Recommended Modern Setup

Instead of maintaining a separate Node/TypeScript MCP server for each subsystem, use a small set of **upstream/community MCP servers plus generic ones**:

- **`mcp-nomad` (Go-based Nomad MCP server)**  
  - Repository: `https://github.com/kocierik/mcp-nomad`  
  - NPM package: `@kocierik/mcp-nomad` (prebuilt CLI + Docker + Go source)  
  - Speaks MCP over stdio/SSE and talks directly to your Nomad cluster.

- **Official Terraform MCP server (`terraform-mcp-server`)**  
  - Repository: `https://github.com/hashicorp/terraform-mcp-server`  
  - Docker image: `hashicorp/terraform-mcp-server:<version>` (see HashiCorp docs for latest)  
  - Gives AI agents real-time access to Terraform Registry docs, modules, and HCP Terraform / TFE workspaces.

- **Filesystem MCP server**  
  - Lets AI agents read/write/search this repository (`hashi_homelab`) so they understand jobs, Terraform, Ansible, docs, etc.

- **Shell MCP server**  
  - Runs commands like `nomad job status`, `terraform plan`, `ansible-playbook`, `consul catalog services`, `vault status`, etc.

- **HTTP MCP server**  
  - Makes HTTP calls to Nomad, Consul, Vault, Proxmox, Traefik, Prometheus APIs when raw API access is needed.

### Example: Nomad via `mcp-nomad`

Use either the global CLI or `npx`:

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

Or, after installing the CLI:

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

### Example: Generic Filesystem / Shell / HTTP

Install the filesystem, shell, and HTTP MCP servers of your choice (from the official MCP ecosystem or other community projects), then point them at this repo and your homelab:

- **Filesystem**: root at `/Users/jackharter/Developer/hashi_homelab`
- **Shell**: working directory `/Users/jackharter/Developer/hashi_homelab`
- **HTTP**: used to call `NOMAD_ADDR`, `CONSUL_ADDR`, `VAULT_ADDR`, `PROMETHEUS_ADDR`, Proxmox API, Traefik API, etc.

Your `mcpServers` block might look conceptually like:

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

> **Note:** The binary names above are placeholders. Use whatever filesystem/shell/HTTP MCP servers you install from the MCP ecosystem.

### Example: Terraform via official Terraform MCP server

Follow the HashiCorp docs for exact version pinning. A Cursor/Claude-style config using Docker might look like:

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

> **Note:** `TFE_ADDRESS` / `TFE_TOKEN` can point at HCP Terraform/TFE or be omitted if you only care about public registry data. Treat tokens as secrets and do not commit them.

## Security Considerations

⚠️ **Important Security Notes:**

1. **Token Management**: MCP servers run with your credentials. Use read-only tokens when possible.
2. **Network Access**: Servers need network access to your homelab. Consider VPN if accessing remotely.
3. **Permissions**: Each server inherits your user permissions. Be cautious with destructive operations.
4. **Secrets**: Never commit tokens or passwords. Use environment variables.

## Contributing

These local TypeScript MCP servers are now considered **legacy**. For new integrations:

1. Prefer **upstream/community MCP servers** (like `mcp-nomad`) when available.
2. Use **generic filesystem/shell/http MCP servers** to give AI agents broad access to your homelab.
3. Only create a new custom MCP server when:
   - There is no suitable community option, and
   - You need a stable, re-usable abstraction (not just a thin CLI wrapper).

## Resources

- [MCP Documentation](https://modelcontextprotocol.io/)
- [MCP TypeScript SDK](https://github.com/modelcontextprotocol/typescript-sdk)
- [Nomad API Docs](https://developer.hashicorp.com/nomad/api-docs)
- [Consul API Docs](https://developer.hashicorp.com/consul/api-docs)
- [Vault API Docs](https://developer.hashicorp.com/vault/api-docs)

## License

MIT
