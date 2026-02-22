# Service Deployment Status - Feb 16, 2026

## Changes Made

### 1. Updated Homepage Configuration
**File:** `configs/homepage/services.yaml`

**Removed (no job files exist):**
- Docker Registry (`) - No job file found  
- Seafile - No job file found

**Kept (services now deploying or already deployed):**
- Gitea (deploying)
- Code Server (deploying)
- Gollum Wiki (deploying)
- Speedtest (already deployed)

### 2. Services Deployed
The following `nomad job run` commands were executed:
- `gitea` - jobs/services/development/gitea/gitea.nomad.hcl
- `codeserver` - jobs/services/development/codeserver/codeserver.nomad.hcl  
- `gollum` - jobs/services/development/gollum/gollum.nomad.hcl
- `netdata` - jobs/system/netdata.nomad.hcl

### 3. Copilot Instructions Updated
Added reminder to always run `source .credentials` before Vault commands.

## Manual Verification Needed

### Check Deployment Status
```fish
# List all current jobs
curl -s http://10.0.0.50:4646/v1/jobs | python3 -c "import sys, json; [print(j['Name']) for j in sorted(json.load(sys.stdin), key=lambda x: x['Name'])]"

# Check specific service status
nomad job status gitea
nomad job status codeserver
nomad job status gollum
nomad job status netdata
```

### Sync Homepage Config & Restart
```fish
# Sync config files to NAS
cd ansible && ansible-playbook playbooks/sync-homepage-config.yml

# Redeploy homepage to pick up changes
nomad job run jobs/services/infrastructure/homepage/homepage.nomad.hcl
```

Or use the task command:
```fish
task homepage:update
```

### Access Services
Once deployed and healthy, these services should be accessible at:
- **Gitea:** https://gitea.lab.hartr.net
- **Code Server:** https://code.lab.hartr.net
- **Gollum Wiki:** https://wiki.lab.hartr.net
- **Netdata:** https://netdata.lab.hartr.net (if configured in Traefik)

## Troubleshooting

### If Services Show Unhealthy
Gitea was showing health check failures during deployment. Check:
```fish
# Get allocation ID
nomad job status gitea

# Check logs
nomad alloc logs -stderr <alloc-id>

# Check if database is accessible
nomad alloc exec <alloc-id> nc -zv <postgres-ip> 5432
```

### If Homepage Doesn't Update
1. Verify files synced: `ssh ubuntu@10.0.0.60 "cat /mnt/nas/homepage/services.yaml | grep -A 5 Services"`
2. Restart homepage: `nomad job run jobs/services/infrastructure/homepage/homepage.nomad.hcl`
3. Check homepage logs: `nomad job status homepage` then `nomad alloc logs <alloc-id>`

## Services With Job Files But Not Yet Deployed
These have job definitions but weren't in the homepage and weren't deployed:
- woodpecker (jobs/services/development/woodpecker/)
- mariadb (jobs/services/databases/mariadb/)
- drawio (jobs/services/media/drawio/)
- paperless (jobs/services/media/paperless/)
- whoami (jobs/services/infrastructure/whoami/)

Deploy if needed:
```fish
nomad job run jobs/services/<category>/<service>/<service>.nomad.hcl
```

## Next Steps
1. ✅ Verify all services are running and healthy
2. ✅ Confirm homepage displays correctly with updated service list  
3. ✅ Test access to newly deployed services
4. ⏳ Decide if optional services (woodpecker, paperless, etc.) should be deployed
5. ⏳ Add netdata to homepage monitoring section if desired
