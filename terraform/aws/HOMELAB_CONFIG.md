# Homelab-Specific Deployment Notes

## Your Infrastructure Configuration

### Traefik Deployment
- **Type**: System job (runs on every Nomad client)
- **Nodes**: 3 Nomad clients
  - 10.0.0.60 (primary DNS target)
  - 10.0.0.61
  - 10.0.0.62
- **Load Balancing**: Handled by Consul service discovery
- **Certificate Storage**: Shared via NFS-backed host volume `/opt/traefik/acme`

### DNS Configuration
- **Home DNS**: `*.lab.hartr.net` → `10.0.0.60`
- **Route 53 (AWS)**: `*.lab.hartr.net` → `10.0.0.60` (for Let's Encrypt validation)
- **Purpose**: Route 53 provides public DNS for Let's Encrypt DNS-01 challenge, while home DNS routes actual traffic

### Traffic Flow
```
1. Client (home network) → https://grafana.lab.hartr.net
2. Home DNS resolves → 10.0.0.60
3. Traefik on 10.0.0.60 receives request
4. Traefik queries Consul for "grafana" service
5. Consul returns healthy instance (could be on any node)
6. Traefik proxies request with SSL termination
```

### Certificate Management
- **Let's Encrypt validation**: DNS-01 challenge via Route 53
- **Certificate sharing**: All 3 Traefik instances share the same ACME storage
- **Renewal**: Automatic, coordinated across nodes via shared storage
- **Storage location**: `/opt/traefik/acme/acme.json` on each node

## Quick Reference

### Terraform Configuration
File: `terraform/aws/terraform.tfvars`
```hcl
aws_region = "us-east-1"
traefik_server_ip = "10.0.0.60"  # Primary endpoint, matches home DNS
```

### Nomad Variables Required
```bash
nomad var put nomad/jobs/traefik \
  aws_access_key="<from terraform output>" \
  aws_secret_key="<from terraform output>" \
  aws_hosted_zone_id="<from terraform output>"
```

### Verify Deployment
```bash
# Check all Traefik instances are running
nomad job status traefik
# Should show: 3/3 allocations running

# Check certificate on primary node
ssh ubuntu@10.0.0.60 "sudo ls -lh /opt/traefik/acme/"
# Should show: acme.json with certificate data

# Test DNS resolution
dig +short calibre.lab.hartr.net
# Should return: 10.0.0.60

# Access Traefik dashboards
# Primary: http://10.0.0.60:8080
# Secondary: http://10.0.0.61:8080  
# Tertiary: http://10.0.0.62:8080
```

### Service Access URLs
After deployment, services are accessible at:
- Grafana: `https://grafana.lab.hartr.net`
- Prometheus: `https://prometheus.lab.hartr.net`
- Calibre: `https://calibre.lab.hartr.net`
- Traefik Dashboard: `http://traefik.lab.hartr.net:8080` (or via direct IP)

All traffic uses valid Let's Encrypt SSL certificates with automatic renewal.
