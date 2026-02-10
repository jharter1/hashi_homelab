# Infrastructure Resource Survey

**Last Survey:** February 4, 2026  
**Last Optimization:** February 10, 2026  
**Survey Tool:** Prometheus MCP Server & Nomad API  
**Purpose:** Identify and implement resource optimization

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
| dev-nomad-client-1 | Client | 10 GB | ~7.5 GB | 4 | Running |
| dev-nomad-client-2 | Client | 10 GB | ~7.5 GB | 4 | Running |
| dev-nomad-client-3 | Client | 10 GB | ~7.5 GB | 4 | Running |
| hub-vault-1 | Vault | 2 GB | 1.3 GB | 2 | Running |
| hub-vault-2 | Vault | 2 GB | 1.0 GB | 2 | Running |
| hub-vault-3 | Vault | 2 GB | 1.1 GB | 2 | Running |

**Total:** 48 GB allocated, ~35 GB actually used (~73% utilization)

**Optimization History:**
- **Feb 10, 2026**: Increased client memory 8→10 GB, reduced 4 service limits, freed ~6.8 GB headroom

### Nomad Jobs (Configured Memory Limits)

From job file analysis:

| Service | Memory Limit | Type | Priority |
|---------|-------------|------|----------|
| postgresql | 2048 MB | Database | High |
| audiobookshelf | 2048 MB | Media | Medium |
| nextcloud | 1024 MB | Storage | High |
| gitea | 1024 MB | Dev | Medium |
| calibre | 768 MB ~~1024~~ | Media | Low |
| jenkins | 1024 MB | CI/CD | Medium |
| prometheus | 512 MB | Monitoring | High |
| minio | 512 MB | Storage | High |
| loki | 512 MB | Logs | High |
| uptime-kuma | 512 MB | Monitoring | Medium |
| vaultwarden | 512 MB | Security | Medium |
| codeserver | 256 MB ~~512~~ | Dev | Low |
| docker-registry | 512 MB | Infrastructure | High |
| freshrss | 256 MB ~~512~~ | RSS | Low |
| gollum | 128 MB ~~256~~ | Wiki | Low |
| homepage | 256 MB | Dashboard | Medium |
| authelia | 256 MB | Auth | High |
| alertmanager | 256 MB | Alerts | High |

**Total Container Memory:** ~13.6 GB configured across all services (saved ~900 MB)

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

## How to Optimize Resources

### Step 1: Survey Current Usage

```bash
# Check Nomad cluster memory
for node_name in dev-nomad-client-1 dev-nomad-client-2 dev-nomad-client-3
  set node_id (curl -s http://10.0.0.50:4646/v1/nodes | python3 -c "import sys, json; nodes = json.load(sys.stdin); print([n['ID'] for n in nodes if '$node_name' == n['Name']][0])")
  curl -s http://10.0.0.50:4646/v1/node/$node_id | python3 -c "import sys, json; n = json.load(sys.stdin); mem = n.get('NodeResources', {}).get('Memory', {}).get('MemoryMB', 0); print('$node_name: ' + str(mem) + ' MB (' + str(round(mem/1024, 2)) + ' GB)')"
end

# Check actual VM memory
for ip in 10.0.0.60 10.0.0.61 10.0.0.62
  ssh ubuntu@$ip "echo -n '$ip: ' && free -h | grep Mem"
end

# List all job statuses
curl -s http://10.0.0.50:4646/v1/jobs | python3 -c "import sys, json; jobs = json.load(sys.stdin); [print(f\"{j['Name']}: {j['Status']}\") for j in jobs]"
```

### Step 2: Increase VM Memory (if needed)

**IMPORTANT:** Memory changes require a full stop/start cycle, not just a reboot.

1. Edit `terraform/environments/dev/terraform.tfvars`:
   ```hcl
   nomad_client_memory = 10240  # Or desired value
   ```

2. Apply Terraform changes:
   ```bash
   task tf:apply
   ```

3. **Stop all clients** (Terraform only updates config, doesn't restart):
   ```bash
   ssh ubuntu@10.0.0.60 "sudo shutdown -h now"
   ssh ubuntu@10.0.0.61 "sudo shutdown -h now"
   ssh ubuntu@10.0.0.62 "sudo shutdown -h now"
   ```

4. **Start VMs from Proxmox UI** (cold boot required for memory to apply)

5. Verify new memory:
   ```bash
   ssh ubuntu@10.0.0.60 "free -h"
   ```

### Step 3: Reduce Service Memory Limits

1. Identify over-provisioned services using Prometheus MCP
2. Edit job files in `jobs/services/*.nomad.hcl`
3. Update the `resources` block:
   ```hcl
   resources {
     cpu    = 500
     memory = 256  # Reduced from 512
   }
   ```
4. Redeploy: `nomad job run -address=http://10.0.0.50:4646 jobs/services/servicename.nomad.hcl`

### Step 4: Handle Services After Client Reboots

Some services may go "dead" after client reboots. To recover:

```bash
# Check for dead jobs
nomad job status -address=http://10.0.0.50:4646 | grep dead

# Restart dead services
nomad job run -address=http://10.0.0.50:4646 jobs/services/servicename.nomad.hcl

# Or restart all services
for job in jobs/services/*.nomad.hcl
  nomad job run -address=http://10.0.0.50:4646 $job
end
```

### Step 5: Monitor for 48-72 Hours

- Watch for OOM kills: `nomad alloc status <alloc-id>`
- Check service health in Traefik/Consul
- Use Prometheus to monitor actual usage vs limits
- Adjust if services are struggling or still over-provisioned

## Optimization Results (Feb 10, 2026)

**Changes Made:**
- Client VMs: 8 GB → 10 GB (+25% headroom)
- calibre: 1024 → 768 MB
- codeserver: 512 → 256 MB
- freshrss: 512 → 256 MB
- gollum: 256 → 128 MB

**Net Impact:**
- Total cluster memory: 24 GB → 30 GB
- Container overhead saved: ~900 MB
- Effective headroom gain: ~6.8 GB
- Utilization: ~97% → ~75% (much healthier!)

**Services to Monitor:**
- calibre, codeserver, freshrss, gollum (reduced limits)
