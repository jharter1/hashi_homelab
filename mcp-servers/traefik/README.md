# Traefik MCP Server

Model Context Protocol (MCP) server for Traefik reverse proxy management. Query routers, services, middleware, and entrypoints through AI assistants.

## Features

- 🔀 **Router Management**: List and inspect HTTP/TCP routers
- 🎯 **Service Discovery**: View service backends and load balancing
- 🔧 **Middleware Inspection**: Check middleware configurations
- 🚪 **Entrypoint Monitoring**: List configured entrypoints (ports)
- 📊 **Overview Dashboard**: Get Traefik version and provider information

## Installation

```bash
cd mcp-servers/traefik
npm install
npm run build
```

## Configuration

### Environment Variables

- `TRAEFIK_API` - Traefik API endpoint (default: `http://10.0.0.60:8080`)

**Note:** Traefik API must be enabled in your Traefik configuration. By default, it runs on port 8080.

### MCP Settings

Add to your MCP configuration:

```json
{
  "mcpServers": {
    "traefik": {
      "command": "node",
      "args": [
        "/Users/jackharter/Developer/hashi_homelab/mcp-servers/traefik/dist/index.js"
      ],
      "env": {
        "TRAEFIK_API": "http://10.0.0.60:8080"
      }
    }
  }
}
```

## Available Tools

### `traefik_overview`
Get Traefik overview including version, providers, and features.

**Example:**
```
What version of Traefik is running?
```

### `traefik_list_routers`
List all HTTP routers configured in Traefik.

**Parameters:**
- `status` (optional): Filter by 'enabled', 'disabled', or 'all' (default: 'all')

**Example:**
```
List all enabled HTTP routers
```

### `traefik_router_details`
Get detailed information about a specific router.

**Parameters:**
- `router_id` (required): Router ID (e.g., 'grafana@consulcatalog')

**Example:**
```
Show me details for the grafana router
```

### `traefik_list_services`
List all services (backends) configured in Traefik.

**Parameters:**
- `status` (optional): Filter by status

**Example:**
```
What services are registered in Traefik?
```

### `traefik_service_details`
Get detailed information about a specific service.

**Parameters:**
- `service_id` (required): Service ID

### `traefik_list_middlewares`
List all middleware configurations.

**Parameters:**
- `status` (optional): Filter by status

**Example:**
```
What middleware is configured?
```

### `traefik_entrypoints`
List all entrypoints (listening ports).

**Example:**
```
What ports is Traefik listening on?
```

### `traefik_tcp_routers`
List all TCP routers (non-HTTP traffic).

**Example:**
```
Show me TCP routers
```

## Usage Examples

Once configured, ask your AI:

- "What routers are configured in Traefik?"
- "Show me the grafana router configuration"
- "Which services are unhealthy?"
- "List all middleware"
- "What entrypoints are defined?"
- "Is the prometheus service reachable?"

## Architecture

This MCP server communicates with the Traefik API endpoint (typically port 8080) to retrieve routing configuration and service status.

```
AI Assistant → MCP Server → Traefik API (port 8080) → Routing Configuration
```

## Enabling Traefik API

If the API isn't enabled, add to your Traefik configuration:

**Static configuration (traefik.nomad.hcl):**
```hcl
config {
  args = [
    "--api.insecure=true",  # Enable API on port 8080
    "--api.dashboard=true",  # Enable dashboard
    # ... other args
  ]
}
```

Or via configuration file:
```yaml
api:
  insecure: true
  dashboard: true
```

**Note:** For production, use secure API authentication instead of `insecure=true`.

## Troubleshooting

**Connection refused:**
- Verify Traefik API is enabled
- Check `TRAEFIK_API` points to correct host/port
- Ensure port 8080 is accessible

**Empty results:**
- Check if services are registered in Consul
- Verify Traefik is discovering services from Consul Catalog
- Review Traefik logs: `nomad alloc logs <traefik-alloc-id>`

**404 errors:**
- Ensure you're using the correct router/service ID format
- IDs typically include provider suffix (e.g., '@consulcatalog')

## Integration with Other MCP Servers

Combine with other servers for powerful queries:

- **With Nomad**: "Is grafana job running AND is the Traefik router configured?"
- **With Consul**: "What services are in Consul but missing in Traefik?"
- **With Proxmox**: "Which VMs are running Traefik instances?"

## Security Notes

⚠️ **Important:** The Traefik API can expose sensitive configuration. For production:
- Use API authentication (username/password or token)
- Restrict API access to internal networks
- Don't expose API port externally

## Development

### Run in dev mode:
```bash
npm run dev
```

### Watch mode:
```bash
npm run watch
```

### Test with inspector:
```bash
npx @modelcontextprotocol/inspector node dist/index.js
```

## License

MIT
