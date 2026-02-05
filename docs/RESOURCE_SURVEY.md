# Infrastructure Resource Survey

**Survey Date:** February 4, 2026  
**Survey Tool:** Prometheus MCP Server  
**Purpose:** Identify resource optimization opportunities

## How to Use This Survey

With the new **Prometheus MCP Server** installed, you can now ask your AI assistant questions like:

- "Show me top 10 containers by memory usage"
- "What VMs are using the most CPU?"
- "Give me a complete resource summary"  
- "Which containers can we reduce memory for?"
- "Show disk usage on /mnt/nas"

## Quick Setup

```bash
# Build the Prometheus MCP server
task mcp:build:prometheus

# Add to your MCP settings
{
  "prometheus": {
    "command": "node",
    "args": ["/.../mcp-servers/prometheus/dist/index.js"],
    "env": { "PROMETHEUS_ADDR": "http://10.0.0.60:9090" }
  }
}
```

## Available Tools

The Prometheus MCP server provides 10 tools for resource monitoring:

1. **prometheus_container_memory** - Current memory usage per container
2. **prometheus_container_cpu** - Current CPU usage per container
3. **prometheus_vm_memory** - Memory usage for VMs/nodes
4. **prometheus_vm_cpu** - CPU usage for VMs/nodes
5. **prometheus_disk_usage** - Disk usage across nodes
6. **prometheus_nomad_allocations** - Nomad task resource usage
7. **prometheus_top_memory_containers** - Top N containers by memory
8. **prometheus_top_cpu_containers** - Top N containers by CPU
9. **prometheus_resource_summary** - Complete cluster overview
10. **prometheus_query** - Custom PromQL queries

## Current Infrastructure (from Proxmox)

### Virtual Machines

| VM Name | Type | Memory (Allocated) | Memory (Used) | CPU Cores | Status |
|---------|------|-------------------|---------------|-----------|--------|
| dev-nomad-server-1 | Server | 4 GB | 1.5 GB | 2 | Running |
| dev-nomad-server-2 | Server | 4 GB | 1.4 GB | 2 | Running |
| dev-nomad-server-3 | Server | 4 GB | 1.4 GB | 2 | Running |
| dev-nomad-client-1 | Client | 8 GB | 7.8 GB | 4 | Running |
| dev-nomad-client-2 | Client | 8 GB | 7.6 GB | 4 | Running |
| dev-nomad-client-3 | Client | 8 GB | 7.8 GB | 4 | Running |
| hub-vault-1 | Vault | 2 GB | 1.3 GB | 2 | Running |
| hub-vault-2 | Vault | 2 GB | 1.0 GB | 2 | Running |
| hub-vault-3 | Vault | 2 GB | 1.1 GB | 2 | Running |

**Total:** 42 GB allocated, ~30 GB actually used (~71% utilization)

### Nomad Jobs (Configured Memory Limits)

From job file analysis:

| Service | Memory Limit | Type | Priority |
|---------|-------------|------|----------|
| postgresql | 2048 MB | Database | High |
| audiobookshelf | 2048 MB | Media | Medium |
| nextcloud | 1024 MB | Storage | High |
| gitea | 1024 MB | Dev | Medium |
| calibre | 1024 MB | Media | Low |
| jenkins | 1024 MB | CI/CD | Medium |
| prometheus | 512 MB | Monitoring | High |
| minio | 512 MB | Storage | High |
| loki | 512 MB | Logs | High |
| uptime-kuma | 512 MB | Monitoring | Medium |
| vaultwarden | 512 MB | Security | Medium |
| codeserver | 512 MB | Dev | Low |
| docker-registry | 512 MB | Infrastructure | High |
| freshrss | 512 MB | RSS | Low |
| gollum | 256 MB | Wiki | Low |
| homepage | 256 MB | Dashboard | Medium |
| authelia | 256 MB | Auth | High |
| alertmanager | 256 MB | Alerts | High |

**Total Container Memory:** ~14.5 GB configured across all services

## Optimization Opportunities

### Use Prometheus MCP to Identify:

1. **Over-Provisioned Containers**
   - Ask: "Which containers are using less than 50% of their allocated memory?"
   - Consider reducing limits for low-utilization services

2. **Under-Provisioned Containers**
   - Ask: "Which containers are at >90% memory usage?"
   - Consider increasing limits or adding resource constraints

3. **VM Memory Pressure**
   - Client VMs at ~97% usage suggests tight memory
   - Ask: "Show VM memory usage trends over the last hour"
   - Consider: Reduce container limits or add more client nodes

4. **Idle Services**
   - Ask: "Which services have 0% CPU usage over 5 minutes?"
   - Consider: Stop or reduce resources for rarely-used services

5. **Peak Usage Times**
   - Use `prometheus_query` with time ranges
   - Identify if services can be scaled down during off-hours

## Expansion Candidates

Services that may need MORE resources (verify with Prometheus):

- **nextcloud** - File sync/storage, often needs more memory
- **postgresql** - Database backing multiple services
- **gitea** - Git operations can be memory-intensive
- **prometheus** - Time-series DB grows over time

## Curtailment Candidates

Services that may need LESS resources (verify with Prometheus):

- **docker-registry** - Mostly idle after image caching
- **gollum** - Lightweight wiki, rarely accessed
- **codeserver** - Development tool, used intermittently
- **freshrss** - Simple RSS reader
- **homepage** - Static dashboard

## Next Steps

1. **Ask Prometheus for Real Data:**
   ```
   "Show me a complete resource summary"
   "Which containers are using the most memory?"
   "What's the actual CPU usage for each VM?"
   ```

2. **Monitor Over Time:**
   - Track metrics for 1-2 weeks
   - Identify usage patterns
   - Make informed decisions

3. **Implement Changes:**
   - Adjust job file memory limits
   - Redeploy with `nomad job run`
   - Monitor for OOM kills or performance issues

4. **Consider Node Expansion:**
   - Client VMs at 97% memory suggest adding capacity
   - Could add 4th client VM OR reduce container limits
   - Balance cost vs. performance

## Recommended First Actions

1. Run `prometheus_resource_summary` to get baseline
2. Run `prometheus_top_memory_containers` with limit=20
3. Compare configured limits vs actual usage
4. Identify 3-5 services with >50% overhead
5. Reduce their limits by 25-30%
6. Monitor for stability over 48 hours
