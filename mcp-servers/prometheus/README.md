# Prometheus MCP Server (legacy local implementation)

> **Status: Deprecated in favor of generic HTTP/shell MCP servers**
>
> This directory contains a project-specific Node/TypeScript MCP server for Prometheus. For new setups, prefer using:
> - A **shell MCP server** to run `curl`/CLI queries against Prometheus, and
> - An **HTTP MCP server** to call the Prometheus HTTP API directly.

Model Context Protocol (MCP) server for querying Prometheus metrics to monitor your HashiCorp homelab infrastructure.

## Features

This MCP server provides **10 tools** for comprehensive resource monitoring:

### Resource Monitoring Tools

1. **prometheus_container_memory** - Get memory usage for all containers
2. **prometheus_container_cpu** - Get CPU usage for all containers  
3. **prometheus_vm_memory** - Get memory usage for VMs/nodes
4. **prometheus_vm_cpu** - Get CPU usage for VMs/nodes
5. **prometheus_disk_usage** - Get disk usage across nodes
6. **prometheus_nomad_allocations** - Get resource usage for Nomad tasks
7. **prometheus_top_memory_containers** - Top N containers by memory
8. **prometheus_top_cpu_containers** - Top N containers by CPU
9. **prometheus_resource_summary** - Complete cluster resource overview
10. **prometheus_query** - Execute custom PromQL queries

## Quick Start

### Prerequisites

- Node.js 18+ installed
- Prometheus running at `http://10.0.0.60:9090` (or custom URL via env var)
- Access to Prometheus HTTP API

### Installation

```bash
cd /Users/jackharter/Developer/hashi_homelab/mcp-servers/prometheus
npm install
npm run build
```

### Test the Server

```bash
# Test with MCP inspector
npx @modelcontextprotocol/inspector node dist/index.js
```

## Configuration

### Environment Variables

- `PROMETHEUS_ADDR` - Prometheus API endpoint (default: `http://10.0.0.60:9090`)
- `PROMETHEUS_URL` - Alternative URL (default: `http://prometheus.home`)

### MCP Client Configuration

Add to your MCP settings file (e.g., Claude Desktop):

```json
{
  "mcpServers": {
    "prometheus": {
      "command": "node",
      "args": [
        "/Users/jackharter/Developer/hashi_homelab/mcp-servers/prometheus/dist/index.js"
      ],
      "env": {
        "PROMETHEUS_ADDR": "http://10.0.0.60:9090"
      }
    }
  }
}
```

## Usage Examples

Once configured, you can ask your AI assistant:

**Memory Analysis:**
- "Show me the top 10 containers by memory usage"
- "What's the memory usage for all VMs?"
- "How much memory is the grafana container using?"

**CPU Analysis:**
- "Which containers are using the most CPU?"
- "Show me CPU usage across all nodes"
- "What's the CPU usage for dev-nomad-client-1?"

**Resource Overview:**
- "Give me a complete resource summary of the cluster"
- "What are the top memory and CPU consumers?"
- "Show me disk usage on /mnt/nas"

**Custom Queries:**
- "Query Prometheus for: sum(rate(http_requests_total[5m]))"
- "Run a PromQL query to show network traffic"

## Tool Details

### prometheus_resource_summary

Returns a comprehensive view of your infrastructure:
- All VM memory/CPU usage
- Top 15 containers by memory
- Formatted with GB/MB units and percentages

Example output:
```json
{
  "vms": [
    {
      "instance": "10.0.0.60:9100",
      "memory_used": "7.80 GB",
      "memory_total": "8.00 GB",
      "memory_percent": "97.50%",
      "cpu_usage": "18.96%"
    }
  ],
  "containers": [
    {
      "job": "nextcloud",
      "memory": "1.23 GB"
    }
  ]
}
```

### prometheus_top_memory_containers

Get the biggest memory consumers:

```json
[
  {
    "rank": 1,
    "job": "nextcloud",
    "task": "nextcloud",
    "memory": "1.23 GB"
  },
  {
    "rank": 2,
    "job": "gitea",
    "task": "gitea",
    "memory": "856.45 MB"
  }
]
```

### prometheus_query

Execute any PromQL query for advanced analysis:

```bash
# Query: node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes
# Returns available memory as percentage for all nodes
```

## Integration with Homelab

This MCP server is designed to work with the HashiCorp homelab stack:

- **Prometheus** (`http://10.0.0.60:9090`) - Metrics collection
- **Node Exporter** (port 9100) - VM/host metrics
- **cAdvisor** (via Docker) - Container metrics
- **Nomad** - Allocation metrics

All metrics are scraped by Prometheus from:
- Nomad servers (10.0.0.50-52)
- Nomad clients (10.0.0.60-65)
- Node exporters on all VMs
- Container runtime metrics

## Development

```bash
# Watch mode for development
npm run watch

# Run without building
npm run dev

# Build for production
npm run build
```

## Troubleshooting

### "No container memory data found"

- Verify Prometheus is scraping cAdvisor metrics
- Check that containers have Nomad labels
- Ensure Prometheus is accessible at the configured URL

### Connection errors

```bash
# Test Prometheus connection
curl http://10.0.0.60:9090/api/v1/query?query=up

# Verify node exporter metrics
curl http://10.0.0.60:9090/api/v1/query?query=node_memory_MemTotal_bytes
```

### Empty results

- Check scrape targets in Prometheus: `http://10.0.0.60:9090/targets`
- Verify Prometheus retention settings
- Ensure metrics are being collected (check Prometheus logs)

## Metrics Reference

### Key Prometheus Metrics Used

**Container Metrics:**
- `container_memory_usage_bytes` - Memory usage
- `container_cpu_usage_seconds_total` - CPU time

**Node Metrics:**
- `node_memory_MemTotal_bytes` - Total memory
- `node_memory_MemAvailable_bytes` - Available memory
- `node_cpu_seconds_total` - CPU time per mode
- `node_filesystem_size_bytes` - Filesystem size
- `node_filesystem_avail_bytes` - Available disk space

**Nomad Metrics:**
- `nomad_client_allocs_memory_usage` - Allocation memory
- `nomad_client_allocs_cpu_total_percent` - Allocation CPU

## License

MIT
