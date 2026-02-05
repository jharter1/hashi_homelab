# Traefik SSL Configuration with Route 53

This guide walks through configuring Traefik to automatically provision and manage SSL certificates via Let's Encrypt using DNS-01 challenge with AWS Route 53.

## Overview

We use the `*.lab.hartr.net` subdomain for homelab services (e.g., `calibre.lab.hartr.net`, `prometheus.lab.hartr.net`) to keep them separate from production sites like `blog.hartr.net` and `j.hartr.net`.

### Architecture

```
User → Home DNS (*.lab.hartr.net → 10.0.0.60) → Traefik (any of 3 nodes) → Consul → Services
                                                      ↓
                                         Let's Encrypt ← Route 53 (DNS-01)
```

**Your homelab setup**:
- **Traefik**: System job running on 3 Nomad clients (10.0.0.60, 10.0.0.61, 10.0.0.62)
- **Home DNS**: Points `*.lab.hartr.net` to 10.0.0.60 (primary endpoint)
- **Route 53**: Public DNS for Let's Encrypt validation, mirrors home DNS configuration
- **Consul**: Service discovery and health checking across all 3 nodes
- **Let's Encrypt**: Free SSL/TLS certificate authority using DNS-01 challenge
- **DNS-01 Challenge**: Proves domain ownership by creating TXT records in Route 53

**Traffic flow**:
1. User accesses `https://grafana.lab.hartr.net` from home network
2. Home DNS resolves to 10.0.0.60
3. Request hits Traefik (running on 10.0.0.60 or load-balanced across nodes)
4. Traefik queries Consul for service location
5. Consul returns healthy service instance (could be on any Nomad client)
6. Traefik proxies request to service with SSL termination

## Prerequisites

- Route 53 hosted zone for `hartr.net` configured in AWS
- Nomad cluster running with Traefik already deployed
- Terraform installed and AWS provider configured
- Access to AWS Console or AWS CLI

## Step 1: Create IAM User and DNS Records with Terraform

### 1.1 Configure Variables

Navigate to the Terraform AWS directory:

```bash
cd terraform/aws
```

Create `terraform.tfvars` from the example:

```bash
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
```

Update the IP address to your Traefik server:

```hcl
# terraform.tfvars
aws_region = "us-east-1"

# Your homelab configuration:
# - Traefik runs as system job on 3 Nomad clients: 10.0.0.60, 10.0.0.61, 10.0.0.62
# - Home DNS points to 10.0.0.60 as primary Traefik endpoint
# - Route 53 DNS should match your home DNS configuration
traefik_server_ip = "10.0.0.60"
```

**About your homelab setup**:
- **Traefik deployment**: System job running on all 3 Nomad clients (10.0.0.60-62)
- **DNS routing**: Home DNS resolves `*.lab.hartr.net` → 10.0.0.60
- **Service discovery**: Consul catalog automatically registers services on any node
- **Traffic flow**: Route 53 (public DNS) → 10.0.0.60 (home network) → Traefik → Consul → Services

**Why this works**:
- Let's Encrypt validation uses public DNS (Route 53) pointing to 10.0.0.60
- Your home DNS mirrors this, routing all `*.lab.hartr.net` traffic to the same IP
- Traefik on 10.0.0.60 handles requests, or Consul can route to Traefik instances on other nodes if needed
- All services are accessible via SSL using your home DNS configuration

### 1.2 Apply Terraform Configuration

```bash
# Initialize Terraform
terraform init

# Review what will be created
terraform plan

# Apply the changes
terraform apply
```

This creates:
- IAM user `traefik-letsencrypt` with Route 53 permissions
- IAM policy allowing DNS record modifications
- Access key pair for authentication
- DNS records: `*.lab.hartr.net` and `lab.hartr.net` pointing to your Traefik server

### 1.3 Save AWS Credentials

**IMPORTANT**: The secret access key is only displayed once. Save it immediately:

```bash
# Display the access key ID
terraform output traefik_aws_access_key_id

# Display the secret access key (sensitive)
terraform output -raw traefik_aws_secret_access_key
```

Store these securely - you'll need them in the next step.

## Step 2: Configure Nomad Clients

### 2.1 Update Client Configuration with Ansible

The Ansible role has been updated to create the Traefik ACME directory and configure the host volume. Apply the changes:

```bash
cd /Users/jackharter/Developer/hashi_homelab/ansible

# Apply to all Nomad clients
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags nomad-client

# Or manually on each client
ssh ubuntu@10.0.0.60 "sudo mkdir -p /opt/traefik/acme && sudo chmod 600 /opt/traefik/acme"
ssh ubuntu@10.0.0.61 "sudo mkdir -p /opt/traefik/acme && sudo chmod 600 /opt/traefik/acme"
ssh ubuntu@10.0.0.62 "sudo mkdir -p /opt/traefik/acme && sudo chmod 600 /opt/traefik/acme"
```

### 2.2 Restart Nomad Clients

```bash
# Restart clients to load the new host volume configuration
ansible nomad_clients -i inventory/hosts.yml -m systemd -a "name=nomad state=restarted" --become

# Or manually
ssh ubuntu@10.0.0.60 "sudo systemctl restart nomad"
ssh ubuntu@10.0.0.61 "sudo systemctl restart nomad"
ssh ubuntu@10.0.0.62 "sudo systemctl restart nomad"
```

### 2.3 Verify Host Volume

```bash
# Check that Nomad recognizes the new volume
nomad node status -verbose | grep -A5 "Host Volumes"

# Or check a specific node
nomad node status <node-id> | grep traefik_acme
```

You should see `traefik_acme` in the list of host volumes.

## Step 3: Store AWS Credentials in Nomad Variables

Set environment variables from Terraform outputs:

```bash
cd terraform/aws

export AWS_ACCESS_KEY_ID=$(terraform output -raw traefik_aws_access_key_id)
export AWS_SECRET_ACCESS_KEY=$(terraform output -raw traefik_aws_secret_access_key)
export AWS_HOSTED_ZONE_ID=$(terraform output -raw route53_zone_id)
```

Store in Nomad variables (requires Nomad ACL token if enabled):

```bash
# Set Nomad address if needed
export NOMAD_ADDR=http://10.0.0.50:4646

# Create the variable
nomad var put nomad/jobs/traefik \
  aws_access_key="$AWS_ACCESS_KEY_ID" \
  aws_secret_key="$AWS_SECRET_ACCESS_KEY" \
  aws_hosted_zone_id="$AWS_HOSTED_ZONE_ID"

# Verify it was stored
nomad var get nomad/jobs/traefik
```

**Expected output**:
```
Namespace   = default
Path        = nomad/jobs/traefik
Create Time = 2026-02-05T...

Items
aws_access_key       = AKIA...
aws_secret_key       = <sensitive>
aws_hosted_zone_id   = Z...
```

## Step 4: Deploy Updated Traefik

### 4.1 Stop Existing Traefik Job

```bash
# Stop the current Traefik job
nomad job stop traefik

# Wait for allocations to stop
nomad job status traefik
```

### 4.2 Deploy New Configuration

The Traefik job has been updated with SSL support. Deploy it:

```bash
cd /Users/jackharter/Developer/hashi_homelab

# Plan the deployment
nomad job plan jobs/system/traefik.nomad.hcl

# Deploy (as system job, will run on all 3 Nomad clients)
nomad job run jobs/system/traefik.nomad.hcl

# Verify Traefik is running on all nodes
nomad job status traefik
# Should show 3 allocations (one per client: 10.0.0.60, 10.0.0.61, 10.0.0.62)
```

### 4.3 Monitor Certificate Request

Watch Traefik logs to see the certificate request. Since Traefik runs on all 3 nodes, pick any allocation:

```bash
# Get all allocation IDs
nomad job status traefik

# Follow logs from primary node (10.0.0.60) - replace <alloc-id>
nomad alloc logs -f <alloc-id> traefik

# Note: All 3 Traefik instances share the same ACME storage via host volume,
# so certificate requests are coordinated and shared across nodes
```

**Successful output**:
```
level=info msg="Obtaining ACME certificate for domains [*.lab.hartr.net lab.hartr.net]"
level=info msg="Creating DNS challenge for domain *.lab.hartr.net"
level=info msg="Waiting for DNS propagation..."
level=info msg="The ACME server validated the DNS challenge"
level=info msg="Certificates obtained for domains [*.lab.hartr.net lab.hartr.net]"
```

**Common errors**:
- `error validating DNS challenge`: Check AWS credentials in Nomad variables
- `rate limit exceeded`: Use Let's Encrypt staging server (see troubleshooting)
- `timeout`: DNS propagation may take longer; increase `delayBeforeCheck` in Traefik config

## Step 5: Update Services to Use SSL

Services have been updated to use `*.lab.hartr.net` with SSL. Redeploy them:

### 5.1 Deploy Updated Services

```bash
# Stop and redeploy each service
nomad job stop grafana
nomad job run jobs/services/grafana.nomad.hcl

nomad job stop prometheus
nomad job run jobs/services/prometheus.nomad.hcl

nomad job stop calibre
nomad job run jobs/services/calibre.nomad.hcl
```

### 5.2 Service Configuration Pattern

Each service now includes these Traefik tags:

```hcl
tags = [
  "traefik.enable=true",
  "traefik.http.routers.<service>.rule=Host(`<service>.lab.hartr.net`)",
  "traefik.http.routers.<service>.entrypoints=websecure",
  "traefik.http.routers.<service>.tls=true",
  "traefik.http.routers.<service>.tls.certresolver=letsencrypt",
]
```

**Key changes from previous configuration**:
- `Host()` uses `*.lab.hartr.net` instead of `*.home`
- `entrypoints=websecure` (HTTPS on port 443) instead of `web`
- `tls=true` enables TLS
- `tls.certresolver=letsencrypt` specifies which certificate resolver to use

## Step 6: Verify Everything Works

### 6.1 Check DNS Resolution

```bash
# Verify DNS records
dig +short *.lab.hartr.net
dig +short calibre.lab.hartr.net
dig +short prometheus.lab.hartr.net

# All should return your Traefik server IP (e.g., 10.0.0.60)
```

### 6.2 Test HTTPS Access

```bash
# Test with curl
curl -I https://calibre.lab.hartr.net
curl -I https://prometheus.lab.hartr.net
curl -I https://grafana.lab.hartr.net

# Should return HTTP/2 200 with valid SSL
```

### 6.3 Access Services

Open in your browser:
- Traefik Dashboard: `https://traefik.lab.hartr.net:8080` (insecure API, only accessible from network)
- Grafana: `https://grafana.lab.hartr.net`
- Prometheus: `https://prometheus.lab.hartr.net`
- Calibre: `https://calibre.lab.hartr.net`

### 6.4 Verify Certificate Details

Check the SSL certificate in your browser:
1. Click the lock icon in the address bar
2. View certificate details
3. Verify:
   - Issued by: Let's Encrypt
   - Valid for: `*.lab.hartr.net` and `lab.hartr.net`
   - Expiration: ~90 days from issue date

### 6.5 Check Traefik Dashboard

Access the Traefik dashboard on any of your 3 nodes:
- Primary: `http://10.0.0.60:8080`
- Secondary: `http://10.0.0.61:8080`
- Tertiary: `http://10.0.0.62:8080`

All dashboards should show:
- **Routers**: Your services with TLS enabled
- **Certificates**: `*.lab.hartr.net` certificate with valid status
- **Services**: Consul-discovered services from all nodes

**Note**: Since Traefik runs as a system job, each node has its own dashboard, but they all share the same certificate storage and Consul service catalog.

## Troubleshooting

### Issue: Certificate Not Being Issued

**Symptoms**: Traefik logs show errors during certificate request, or certificate never appears.

**Solutions**:

1. **Check AWS credentials**:
   ```bash
   nomad var get nomad/jobs/traefik
   ```
   Verify `aws_access_key` and `aws_secret_key` are correct.

2. **Verify Route 53 permissions**:
   ```bash
   cd terraform/aws
   terraform state show aws_iam_policy.traefik_route53
   ```
   Ensure policy allows `route53:ChangeResourceRecordSets`.

3. **Test with Let's Encrypt staging server**:
   Edit `jobs/system/traefik.nomad.hcl` and uncomment:
   ```yaml
   caServer: https://acme-staging-v02.api.letsencrypt.org/directory
   ```
   This avoids production rate limits during testing.

4. **Check DNS TXT record creation**:
   ```bash
   dig _acme-challenge.lab.hartr.net TXT
   ```
   During certificate request, you should see TXT records.

5. **Increase DNS propagation delay**:
   In `jobs/system/traefik.nomad.hcl`, increase `delayBeforeCheck`:
   ```yaml
   dnsChallenge:
     delayBeforeCheck: 60s  # Increase from 30s
   ```

### Issue: DNS Not Resolving

**Symptoms**: `dig` commands return `NXDOMAIN` or no results.

**Solutions**:

1. **Verify Terraform applied successfully**:
   ```bash
   cd terraform/aws
   terraform output dns_records_created
   ```

2. **Check Route 53 console**:
   - Login to AWS Console
   - Navigate to Route 53 → Hosted Zones → hartr.net
   - Verify A records exist for `*.lab.hartr.net` and `lab.hartr.net`

3. **Test with different DNS server**:
   ```bash
   dig @8.8.8.8 calibre.lab.hartr.net
   dig @1.1.1.1 calibre.lab.hartr.net
   ```

4. **DNS propagation delay**:
   Wait 5-10 minutes for DNS changes to propagate globally.

### Issue: Services Not Accessible

**Symptoms**: DNS resolves, but HTTPS connection fails or times out.

**Solutions**:

1. **For internal IP configuration**:
   - Ensure you're accessing from within your home network
   - Public DNS resolves to internal IP, which only works internally

2. **For public IP configuration**:
   - Verify firewall allows ports 80 and 443
   - Check port forwarding on router if behind NAT
   - Ensure Traefik is binding to correct IP

3. **Check Traefik routing**:
   ```bash
   # Visit Traefik dashboard
   open http://<traefik-ip>:8080

   # Or use curl
   curl http://<traefik-ip>:8080/api/http/routers
   ```

4. **Verify service registration in Consul**:
   ```bash
   consul catalog services
   consul catalog service grafana
   ```

### Issue: Rate Limits Hit

**Symptoms**: Traefik logs show "too many certificates already issued" or similar errors.

**Context**: Let's Encrypt has rate limits:
- 50 certificates per registered domain per week
- Wildcard certificates count as one certificate

**Solutions**:

1. **Use staging server during testing** (already mentioned above)

2. **Wait for rate limit to reset** (usually 1 week)

3. **Use wildcard certificate**:
   The current configuration requests a wildcard `*.lab.hartr.net` certificate, which covers all services with a single cert. This is efficient and conserves rate limits.

4. **Check current rate limit status**:
   Visit: https://crt.sh/?q=%.lab.hartr.net

### Issue: Certificate Renewal Fails

**Symptoms**: Certificates expire and aren't renewed automatically.

**Solutions**:

1. **Check Traefik logs during renewal window** (~30 days before expiration):
   ```bash
   nomad alloc logs -f <traefik-alloc-id>
   ```

2. **Verify ACME storage is persistent**:
   ```bash
   ssh ubuntu@<traefik-node> "sudo ls -lh /opt/traefik/acme/"
   ```
   Should show `acme.json` file.

3. **Ensure Traefik restarts preserve certificates**:
   The `traefik_acme` host volume is mounted, so certificates persist across restarts.

4. **Manual renewal**:
   Delete `/opt/traefik/acme/acme.json` and restart Traefik to force new certificate request.

### Issue: Terraform State Management

**Symptoms**: Lost credentials, can't rotate keys, or state conflicts.

**Solutions**:

1. **Secure state file**:
   ```bash
   # The terraform.tfstate contains the secret access key
   chmod 600 terraform/aws/terraform.tfstate
   ```

2. **Use remote state** (recommended for production):
   ```hcl
   # In terraform/aws/traefik-route53.tf
   terraform {
     backend "s3" {
       bucket         = "your-terraform-state-bucket"
       key            = "traefik/route53/terraform.tfstate"
       region         = "us-east-1"
       dynamodb_table = "terraform-state-lock"
       encrypt        = true
     }
   }
   ```

3. **Rotate credentials**:
   ```bash
   terraform taint aws_iam_access_key.traefik_letsencrypt
   terraform apply
   # Update Nomad variables with new credentials
   ```

4. **Recover from lost state**:
   If you lose `terraform.tfstate`, you can import existing resources:
   ```bash
   terraform import aws_iam_user.traefik_letsencrypt traefik-letsencrypt
   terraform import aws_iam_policy.traefik_route53 arn:aws:iam::...
   ```

### Issue: HTTP Redirects Not Working

**Symptoms**: Accessing `http://service.lab.hartr.net` doesn't redirect to HTTPS.

**Solution**: This is expected with the current configuration. The Traefik config includes:

```yaml
entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
          permanent: true
```

All HTTP requests should automatically redirect to HTTPS. If not:

1. **Verify Traefik configuration loaded**:
   ```bash
   nomad alloc logs <traefik-alloc-id> | grep -i redirect
   ```

2. **Check browser cache**: Clear browser cache and try again

3. **Test with curl**:
   ```bash
   curl -I http://calibre.lab.hartr.net
   # Should return HTTP 301 or 308 with Location: https://...
   ```

## Adding New Services

To add SSL to new services, use this pattern in your Nomad job file:

```hcl
job "myservice" {
  datacenters = ["dc1"]
  
  group "app" {
    network {
      port "http" {
        to = 8080  # Service's internal port
      }
    }

    service {
      name = "myservice"
      port = "http"
      
      tags = [
        "traefik.enable=true",
        "traefik.http.routers.myservice.rule=Host(`myservice.lab.hartr.net`)",
        "traefik.http.routers.myservice.entrypoints=websecure",
        "traefik.http.routers.myservice.tls=true",
        "traefik.http.routers.myservice.tls.certresolver=letsencrypt",
      ]
    }

    task "app" {
      driver = "docker"
      
      config {
        image = "your/image:latest"
        ports = ["http"]
      }
    }
  }
}
```

**No additional DNS or certificate configuration needed** - the wildcard certificate covers all `*.lab.hartr.net` services automatically!

## Security Considerations

### Credentials Management

- **Nomad Variables**: Encrypted at rest, scoped to jobs
- **Terraform State**: Contains sensitive data - keep secure
- **IAM User**: Minimal permissions (only Route 53)
- **Access Keys**: Rotate periodically using Terraform

### Network Security

- **Internal IP**: Services only accessible from home network
- **Public IP**: Requires firewall rules and port forwarding
- **SSL/TLS**: All traffic encrypted in transit
- **Traefik Dashboard**: Insecure API enabled (port 8080) - only accessible internally

### Best Practices

1. **Use Terraform Cloud or remote state** for production
2. **Enable Nomad ACLs** to restrict variable access
3. **Rotate AWS credentials quarterly**:
   ```bash
   terraform taint aws_iam_access_key.traefik_letsencrypt
   terraform apply
   ```
4. **Monitor certificate expiration** (Traefik handles renewals automatically)
5. **Backup ACME storage** (`/opt/traefik/acme/acme.json`) or rely on automatic renewal

## Summary

**What we built**:

- ✅ Terraform configuration for AWS IAM and Route 53
- ✅ Automated SSL certificate provisioning via Let's Encrypt
- ✅ Wildcard certificate for `*.lab.hartr.net`
- ✅ Automatic HTTP → HTTPS redirects
- ✅ Secure credential storage in Nomad variables
- ✅ Updated services (Grafana, Prometheus, Calibre) with SSL

**Architecture**:

```
User → Home DNS (*.lab.hartr.net → 10.0.0.60)
         ↓
   Traefik (3 nodes: 10.0.0.60-62, SSL/TLS)
         ↓
   Consul Service Discovery
         ↓
   Nomad Services (distributed across clients)

Let's Encrypt ← Route 53 DNS-01 Challenge
```

**Next steps**:

1. Apply Terraform configuration: `cd terraform/aws && terraform apply`
2. Store credentials in Nomad: `nomad var put nomad/jobs/traefik ...`
3. Update Nomad clients: `ansible-playbook playbooks/site.yml --tags nomad-client`
4. Deploy Traefik: `nomad job run jobs/system/traefik.nomad.hcl`
5. Deploy services: `nomad job run jobs/services/grafana.nomad.hcl ...`
6. Verify: Access `https://grafana.lab.hartr.net` in your browser

**Maintenance**:

- Certificates auto-renew ~30 days before expiration
- New services automatically get SSL with correct Traefik tags
- No manual certificate management needed
- Monitor Traefik logs for renewal issues

---

For additional help, see:
- Traefik SSL docs: https://doc.traefik.io/traefik/https/acme/
- Let's Encrypt rate limits: https://letsencrypt.org/docs/rate-limits/
- AWS Route 53 IAM: https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/access-control-managing-permissions.html
