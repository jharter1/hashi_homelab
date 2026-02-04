# Nomad MCP Server - Quick Setup Guide

This guide will help you set up the Nomad MCP server so you can interact with your Nomad cluster through AI assistants.

## Prerequisites

- Node.js 18+ installed
- Access to your Nomad cluster at `http://10.0.0.50:4646`
- VS Code with Claude Dev/Cline extension OR Claude Desktop app

## Setup Steps

### 1. Build the MCP Server

```bash
# From the repository root
task mcp:build:nomad

# Or manually
cd mcp-servers/nomad
npm install
npm run build
```

### 2. Configure Your AI Assistant

#### Option A: VS Code (Claude Dev/Cline)

1. Find your MCP settings file location:
   - **Cline**: `~/Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json`
   - **Claude Dev**: Similar path depending on extension

2. Add the Nomad server configuration:

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

3. Reload VS Code window (Cmd+Shift+P → "Reload Window")

#### Option B: Claude Desktop

1. Open Claude Desktop configuration:
   ```bash
   open ~/Library/Application\ Support/Claude/claude_desktop_config.json
   ```

2. Add the configuration:

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

3. Restart Claude Desktop

### 3. Test It!

Ask your AI assistant:

- "What jobs are running in my Nomad cluster?"
- "Show me the status of the grafana job"
- "Get the last 50 lines of logs from the prometheus allocation"
- "How healthy is my Nomad cluster?"
- "List all Nomad nodes"

## Available Commands

Once configured, you can:

✅ **List jobs**: "What jobs are running?"  
✅ **Check job status**: "What's the status of prometheus?"  
✅ **View logs**: "Show me logs from the grafana allocation"  
✅ **Monitor health**: "Is my Nomad cluster healthy?"  
✅ **View nodes**: "List all Nomad nodes"  
✅ **Stop jobs**: "Stop the test-job"  
✅ **Get allocations**: "Show me allocations for the traefik job"  

## Advanced Configuration

### Using Nomad ACL Tokens

If your cluster uses ACLs, add a token:

```json
{
  "mcpServers": {
    "nomad": {
      "command": "node",
      "args": [
        "/Users/jackharter/Developer/hashi_homelab/mcp-servers/nomad/dist/index.js"
      ],
      "env": {
        "NOMAD_ADDR": "http://10.0.0.50:4646",
        "NOMAD_TOKEN": "your-secret-token-here"
      }
    }
  }
}
```

### Connecting to Different Clusters

You can configure multiple MCP servers for different environments:

```json
{
  "mcpServers": {
    "nomad-dev": {
      "command": "node",
      "args": ["/path/to/dist/index.js"],
      "env": {
        "NOMAD_ADDR": "http://10.0.0.50:4646"
      }
    },
    "nomad-prod": {
      "command": "node",
      "args": ["/path/to/dist/index.js"],
      "env": {
        "NOMAD_ADDR": "http://10.0.1.50:4646",
        "NOMAD_TOKEN": "prod-token"
      }
    }
  }
}
```

## Troubleshooting

### "Connection refused" errors

**Problem**: MCP server can't reach Nomad

**Solutions**:
- Verify Nomad is running: `curl http://10.0.0.50:4646/v1/status/leader`
- Check network connectivity to homelab
- Ensure NOMAD_ADDR is correct in config

### "Unknown tool" errors

**Problem**: AI assistant doesn't see the tools

**Solutions**:
- Rebuild the server: `task mcp:build:nomad`
- Restart VS Code or Claude Desktop
- Check MCP server logs in console/terminal output

### Authorization errors

**Problem**: API returns 403 Forbidden

**Solutions**:
- Add `NOMAD_TOKEN` to environment variables
- Ensure token has appropriate permissions
- Check token is valid: `NOMAD_TOKEN=xxx nomad status`

### Want to see debug output?

Run the MCP server manually to see what's happening:

```bash
cd mcp-servers/nomad
NOMAD_ADDR=http://10.0.0.50:4646 npm run dev
```

## Testing Without AI

Use the MCP Inspector to test the server:

```bash
task mcp:test:nomad

# Or manually
cd mcp-servers/nomad
npx @modelcontextprotocol/inspector node dist/index.js
```

This opens a web interface where you can test tool calls directly.

## Next Steps

- Explore the [full documentation](README.md)
- Try other MCP servers (Consul, Vault - coming soon!)
- Contribute improvements via pull request

## Quick Reference Card

```bash
# Build the server
task mcp:build:nomad

# Run in dev mode
task mcp:dev:nomad

# Test with inspector
task mcp:test:nomad

# Rebuild after changes
cd mcp-servers/nomad && npm run build
```

---

**Need help?** Check the main [README.md](README.md) or open an issue.
