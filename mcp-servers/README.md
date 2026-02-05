# MCP Servers for Hashi Homelab

This directory contains Model Context Protocol (MCP) servers that enable AI assistants to interact with your HashiCorp homelab infrastructure.

## Available Servers

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

### 1. Install Dependencies

```bash
cd mcp-servers/nomad
npm install
npm run build
```

### 2. Configure Your AI Assistant

#### For VS Code (Claude Dev/Cline)

Add to your MCP settings file:

```json
{
  "mcpServers": {
    "nomad": {
      "command": "node",
      "args": [
        "/Users/jackharter/Developer/hashi_homelab/mcp-servers/nomad/dist/index.js"
      ],
      "env": {
        "NOMAD_ADDR": "http://10.0.0.50:4646"
      }
    }
  }
}
```

#### For Claude Desktop

Add to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "nomad": {
      "command": "node",
      "args": [
        "/Users/jackharter/Developer/hashi_homelab/mcp-servers/nomad/dist/index.js"
      ],
      "env": {
        "NOMAD_ADDR": "http://10.0.0.50:4646"
      }
    }
  }
}
```

### 3. Test It

Ask your AI assistant:
- "What jobs are running in Nomad?"
- "Show me the cluster health"
- "Get logs from the grafana job"

## Future MCP Servers (Ideas)

### Consul MCP Server
- Query service catalog
- Read/write KV store
- Check service health

### Vault MCP Server
- Read secrets (with appropriate permissions)
- Check policy assignments
- Monitor seal status

### Terraform MCP Server
- Validate configurations
- Parse state files
- Plan infrastructure changes

### Ansible MCP Server
- List playbooks and roles
- Check inventory
- Validate YAML syntax

### Infrastructure Health MCP Server
- Aggregate health across all HashiCorp tools
- Monitor NAS storage
- Check Proxmox VM status

## Development

Each MCP server is a standalone Node.js/TypeScript project following the MCP SDK conventions.

**Common commands:**
```bash
npm install     # Install dependencies
npm run build   # Build TypeScript to JavaScript
npm run dev     # Run in development mode
npm run watch   # Watch mode for development
```

## Architecture

```
┌─────────────────┐
│  AI Assistant   │
│  (Claude/GPT)   │
└────────┬────────┘
         │
         │ MCP Protocol
         │
┌────────▼────────┐
│   MCP Server    │
│   (Node.js)     │
└────────┬────────┘
         │
         │ HTTP/API
         │
┌────────▼────────────────┐
│  HashiCorp Services     │
│  • Nomad (10.0.0.50)    │
│  • Consul (10.0.0.50)   │
│  • Vault (10.0.0.30)    │
└─────────────────────────┘
```

## Security Considerations

⚠️ **Important Security Notes:**

1. **Token Management**: MCP servers run with your credentials. Use read-only tokens when possible.
2. **Network Access**: Servers need network access to your homelab. Consider VPN if accessing remotely.
3. **Permissions**: Each server inherits your user permissions. Be cautious with destructive operations.
4. **Secrets**: Never commit tokens or passwords. Use environment variables.

## Contributing

Want to add a new MCP server?

1. Create a new directory under `mcp-servers/`
2. Initialize with `npm init` and install `@modelcontextprotocol/sdk`
3. Implement the server following the pattern in `nomad/`
4. Add documentation
5. Update this README

## Resources

- [MCP Documentation](https://modelcontextprotocol.io/)
- [MCP TypeScript SDK](https://github.com/modelcontextprotocol/typescript-sdk)
- [Nomad API Docs](https://developer.hashicorp.com/nomad/api-docs)
- [Consul API Docs](https://developer.hashicorp.com/consul/api-docs)
- [Vault API Docs](https://developer.hashicorp.com/vault/api-docs)

## License

MIT
