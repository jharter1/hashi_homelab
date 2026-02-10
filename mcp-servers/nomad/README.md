# Nomad MCP Server (legacy local implementation)

> **Status: Deprecated in favor of community `mcp-nomad`**
>
> This directory contains a project-specific Node/TypeScript Nomad MCP server. For new setups, prefer the **Go-based community Nomad MCP server** [`@kocierik/mcp-nomad`](https://github.com/kocierik/mcp-nomad), which ships prebuilt binaries and an NPM CLI.

Model Context Protocol (MCP) server for HashiCorp Nomad cluster management. This allows AI assistants to interact with your Nomad cluster directly.

## Features

- 📊 **Job Management**: List, query, and stop Nomad jobs
- 🔍 **Allocation Monitoring**: View allocation status and logs
- 🏥 **Cluster Health**: Check overall cluster status and node health
- 🔐 **Token Support**: Optional ACL token authentication

## Recommended Alternative: `mcp-nomad`

Instead of building this local server, install and configure `mcp-nomad`:

```bash
npm install -g @kocierik/mcp-nomad
```

Claude / Cursor MCP configuration:

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

Or, using `npx`:

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

## Installation (legacy server)

```bash
cd mcp-servers/nomad
npm install
npm run build
```

## Configuration

### Environment Variables

- `NOMAD_ADDR` - Nomad API address (default: `http://10.0.0.50:4646`)
- `NOMAD_TOKEN` - Optional Nomad ACL token for authentication

### VS Code Configuration

Add to your VS Code MCP settings (`~/Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json` or similar):

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

### Claude Desktop Configuration

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

## Available Tools

### `nomad_list_jobs`
List all jobs in the cluster.

**Parameters:**
- `prefix` (optional): Filter jobs by ID prefix

**Example:**
```
List all jobs starting with "grafana"
```

### `nomad_job_status`
Get detailed status of a specific job.

**Parameters:**
- `job_id` (required): The job ID

**Example:**
```
What's the status of the prometheus job?
```

### `nomad_job_allocations`
Get all allocations for a job.

**Parameters:**
- `job_id` (required): The job ID

### `nomad_allocation_status`
Get detailed information about an allocation.

**Parameters:**
- `alloc_id` (required): The allocation ID

### `nomad_allocation_logs`
Fetch logs from a running allocation.

**Parameters:**
- `alloc_id` (required): The allocation ID
- `task` (required): The task name
- `tail` (optional): Number of lines to tail (default: 100)

**Example:**
```
Show me the last 50 lines of logs from allocation abc123, task grafana
```

### `nomad_node_status`
List all nodes in the cluster with their status.

### `nomad_cluster_health`
Get overall cluster health metrics.

**Example:**
```
How healthy is my Nomad cluster?
```

### `nomad_stop_job`
Stop a running job.

**Parameters:**
- `job_id` (required): The job ID
- `purge` (optional): Purge job from system (default: false)

**Example:**
```
Stop the whoami job
```

## Development

### Run in dev mode (with auto-reload):
```bash
npm run dev
```

### Build:
```bash
npm run build
```

### Watch mode:
```bash
npm run watch
```

## Testing

You can test the MCP server using the MCP Inspector:

```bash
npx @modelcontextprotocol/inspector node dist/index.js
```

## Usage Examples

Once configured, you can ask your AI assistant:

- "What jobs are currently running in Nomad?"
- "Show me the status of the grafana job"
- "Get logs from the prometheus allocation"
- "How many nodes are in the cluster?"
- "Stop the test-job"
- "What's the health of my Nomad cluster?"

## Architecture

This MCP server communicates with the Nomad HTTP API at `http://10.0.0.50:4646` (or your configured address). It translates natural language requests into Nomad API calls and returns structured responses.

```
AI Assistant → MCP Server → Nomad HTTP API → Your Cluster
```

## Troubleshooting

**Connection refused:**
- Verify `NOMAD_ADDR` points to a reachable Nomad server
- Check that port 4646 is accessible
- If using ACLs, ensure `NOMAD_TOKEN` is set

**Authorization errors:**
- Set `NOMAD_TOKEN` environment variable with a valid ACL token
- Ensure the token has appropriate permissions

**Tool not found:**
- Rebuild the server: `npm run build`
- Restart your VS Code or Claude Desktop
- Check MCP server logs in the console

## Security Notes

⚠️ **Important:** This MCP server runs with the permissions of your Nomad token. For production use:
- Use read-only tokens when possible
- Restrict token capabilities to minimum required
- Consider network isolation for sensitive clusters

## License

MIT
