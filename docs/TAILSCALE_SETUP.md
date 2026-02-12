# Tailscale Remote Access Setup

Enable remote access to your homelab services (`*.lab.hartr.net`) from anywhere using Tailscale VPN.

## Quick Start

### 1. Deploy Tailscale (Automated)

```bash
# Deploy on Traefik node first (recommended)
task tailscale:deploy:traefik

# Or deploy on all clients at once
task tailscale:deploy
```

### 2. Authenticate Nodes

The playbook will output authentication URLs. Open them in your browser and approve each device in your Tailscale account.

### 3. Approve Subnet Routes

**Critical**: For remote access to work, approve the subnet route:

1. Go to https://login.tailscale.com/admin/machines
2. Find `nomad-client-1` in the machine list
3. Click **Edit route settings** (or three dots menu)
4. Toggle `10.0.0.0/24` from "Advertised" to **Approved**

### 4. Install Tailscale on Your Devices

**macOS**: `brew install tailscale` then start the app  
**Windows**: Download from https://tailscale.com/download  
**Linux**: `curl -fsSL https://tailscale.com/install.sh | sh`  
**iOS/Android**: Install Tailscale app from app store  

Log in with the same Tailscale account.

### 5. Test Connectivity

```bash
# Ping your homelab network
ping 10.0.0.60

# Access services
curl https://calibre.lab.hartr.net
open https://prometheus.lab.hartr.net
```

## DNS Configuration

You have three options to make `*.lab.hartr.net` work over Tailscale:

### Option A: Tailscale MagicDNS + Global Nameserver (Recommended)

1. Go to https://login.tailscale.com/admin/dns
2. Enable **MagicDNS**
3. Under **Global nameservers**, add your local DNS server:
   - `10.0.0.10` (your local DNS/Pi-hole)

This automatically routes all `.lab.hartr.net` queries through your homelab DNS.

### Option B: Tailscale DNS Overrides

If you don't have a local DNS server, add manual records:

1. Go to https://login.tailscale.com/admin/dns
2. Scroll to **Override local DNS**
3. Add records:
```
calibre.lab.hartr.net → 10.0.0.60
vaultwarden.lab.hartr.net → 10.0.0.60
prometheus.lab.hartr.net → 10.0.0.60
# ... etc
```

### Option C: Local Hosts File (Quick & Dirty)

Edit your hosts file (`/etc/hosts` on macOS/Linux or `C:\Windows\System32\drivers\etc\hosts` on Windows):

```
10.0.0.60 calibre.lab.hartr.net
10.0.0.60 vaultwarden.lab.hartr.net
10.0.0.60 prometheus.lab.hartr.net
10.0.0.60 nomad.lab.hartr.net
10.0.0.60 consul.lab.hartr.net
```

## Available Task Commands

```bash
# Deploy Tailscale
task tailscale:deploy              # Deploy on all clients
task tailscale:deploy:traefik      # Deploy only on Traefik node

# Check status
task tailscale:status              # Show Tailscale status on all clients
task tailscale:ip                  # Get Tailscale IPs for all clients
```

## Manual Deployment (Without Task)

```bash
# Deploy on all clients
cd ansible
ansible-playbook playbooks/deploy-tailscale.yml

# Deploy only on Traefik node
ansible-playbook playbooks/deploy-tailscale.yml --limit nomad-client-1

# Use auth key for unattended install (get from Tailscale admin)
ansible-playbook playbooks/deploy-tailscale.yml -e "tailscale_auth_key=tskey-auth-xxxxx"
```

## Configuration Details

### Subnet Routing

Only `nomad-client-1` (the Traefik node) advertises subnet routes:
- **Advertises**: `10.0.0.0/24` (entire homelab network)
- **Other nodes**: Connect individually without advertising routes

This allows you to access all homelab services through one tunnel.

### Variables

The playbook uses these variables (defined in [deploy-tailscale.yml](../ansible/playbooks/deploy-tailscale.yml)):

```yaml
# Advertise subnet routes (only on nomad-client-1)
tailscale_advertise_routes: "10.0.0.0/24"

# Don't override local DNS
tailscale_accept_dns: false

# Use inventory hostname
tailscale_hostname: "{{ inventory_hostname }}"

# Optional auth key (for unattended install)
# tailscale_auth_key: "tskey-auth-xxxxx"
```

## Architecture

```
User Device (anywhere)
  ↓ (Tailscale tunnel)
Nomad Client 1 (10.0.0.60)
  ↓ (advertises 10.0.0.0/24 subnet)
Entire Homelab Network
  ├── 10.0.0.50-52 (Nomad servers)
  ├── 10.0.0.60-65 (Nomad clients)
  └── All services via Traefik
```

## Troubleshooting

### Can't ping 10.0.0.60 from Tailscale

**Solution**:
1. Verify subnet route is **approved** in Tailscale admin (not just advertised)
2. Check status: `ssh ubuntu@10.0.0.60 "sudo tailscale status"`
3. Restart Tailscale: `ssh ubuntu@10.0.0.60 "sudo systemctl restart tailscaled"`

### Services not accessible

**Check Traefik is running**:
```bash
nomad job status traefik
```

**Verify DNS resolution**:
```bash
# Should return 10.0.0.60
nslookup calibre.lab.hartr.net

# If not, try direct IP first
curl https://10.0.0.60
```

### SSL certificate warnings

Use domain names, not IPs:
- ❌ `https://10.0.0.60` (will show cert warning)
- ✅ `https://calibre.lab.hartr.net` (uses Let's Encrypt cert)

### Authentication URL not showing

The playbook displays the authentication URL if Tailscale isn't logged in. If you missed it:

```bash
ssh ubuntu@10.0.0.60
sudo tailscale up --advertise-routes=10.0.0.0/24 --hostname=nomad-client-1
# Will output: To authenticate, visit: https://login.tailscale.com/a/xxxxx
```

## Security Recommendations

### Tailscale ACLs

Restrict access by editing ACLs at https://login.tailscale.com/admin/acls

Example ACL to allow specific users access to homelab:

```json
{
  "acls": [
    {
      "action": "accept",
      "src": ["user@example.com"],
      "dst": ["10.0.0.0/24:*"]
    }
  ]
}
```

### Traefik Authentication

Add authentication middleware for sensitive services:

```hcl
# In Nomad job files
tags = [
  "traefik.enable=true",
  "traefik.http.routers.myapp.middlewares=auth@file",
]
```

### Two-Factor Authentication

Enable 2FA on your Tailscale account:
1. Go to https://login.tailscale.com/admin/settings/account
2. Enable two-factor authentication

## What You Can Access Remotely

✅ All services at `https://*.lab.hartr.net`  
✅ Nomad UI: `http://10.0.0.50:4646` or `http://nomad.lab.hartr.net:4646`  
✅ Consul UI: `http://10.0.0.50:8500` or `http://consul.lab.hartr.net:8500`  
✅ Traefik Dashboard: `http://10.0.0.60:8080` or `http://traefik.lab.hartr.net:8080`  
✅ Homepage Dashboard: `https://homepage.lab.hartr.net`  
✅ SSH to all VMs: `ssh ubuntu@10.0.0.60`  

## Uninstall Tailscale

```bash
# On each client
ssh ubuntu@10.0.0.60 "sudo tailscale down && sudo apt-get remove -y tailscale"
```

## References

- **Tailscale Admin**: https://login.tailscale.com/admin
- **Subnet Routes Docs**: https://tailscale.com/kb/1019/subnets
- **ACL Documentation**: https://tailscale.com/kb/1018/acls
- **MagicDNS**: https://tailscale.com/kb/1081/magicdns

---

**Next Steps After Setup**:
1. Install Tailscale on your phone for mobile access
2. Configure Tailscale ACLs if sharing access with others
3. Set up Traefik authentication for sensitive services
4. Explore Tailscale Funnel for public exposure (if needed)
