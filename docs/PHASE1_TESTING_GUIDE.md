# Phase 1 Testing Guide

**Goal:** Validate config externalization changes work correctly on the live cluster before continuing.

## Pre-Flight Checklist

### ✅ Environment Verification
```fish
# 1. Verify cluster is accessible
nomad node status
consul members

# 2. Verify NAS mount exists on clients
ssh ubuntu@10.0.0.60 "ls -la /mnt/nas"

# 3. Check current service status
nomad job status traefik
nomad job status prometheus
nomad job status grafana
nomad job status loki
nomad job status alertmanager

# 4. Capture baseline metrics (optional)
curl -s http://prometheus.home/api/v1/query?query=up | jq
```

## Testing Steps

### Step 1: Validate Locally
```fish
# Run full validation suite
task validate:all

# Expected output:
# ✅ Packer templates valid
# ✅ Terraform valid
# ✅ Nomad jobs validated
# ✅ Ansible playbooks valid
# ✅ All configs validated successfully
```

**If validation fails:** Fix issues before proceeding.

---

### Step 2: Sync Configs to Cluster
```fish
# Sync all externalized configs to /mnt/nas/configs/
task configs:sync
```

**Expected output:**
```
📤 Syncing configuration files...
PLAY [Sync configuration files] ***

TASK [config-sync : Create configs directory on NAS] ***
ok: [dev-nomad-client-1]

TASK [config-sync : Sync Traefik config] ***
changed: [dev-nomad-client-1]

TASK [config-sync : Sync Prometheus config] ***
changed: [dev-nomad-client-1]

...

✅ Configs synced successfully
```

**Verify sync:**
```fish
# Check files exist on NAS
ssh ubuntu@10.0.0.60 "tree /mnt/nas/configs/"

# Expected structure:
# /mnt/nas/configs/
# ├── infrastructure/
# │   └── traefik/
# │       └── traefik.yml
# ├── observability/
# │   ├── alertmanager/
# │   │   └── alertmanager.yml
# │   ├── grafana/
# │   │   ├── dashboards.yml
# │   │   └── datasources.yml
# │   ├── loki/
# │   │   └── loki.yaml
# │   └── prometheus/
# │       └── prometheus.yml
```

---

### Step 3: Validate Nomad Jobs
```fish
# Validate all updated job files
nomad job validate jobs/system/traefik.nomad.hcl
nomad job validate jobs/services/observability/prometheus/prometheus.nomad.hcl
nomad job validate jobs/services/observability/grafana/grafana.nomad.hcl
nomad job validate jobs/services/observability/loki/loki.nomad.hcl
nomad job validate jobs/services/observability/alertmanager/alertmanager.nomad.hcl
```

**Expected:** All should show "Job validation successful"

---

### Step 4: Deploy Services (One at a Time)

**Strategy:** Deploy incrementally to catch issues early.

#### 4a. Deploy Traefik (System Service)
```fish
# Deploy
nomad job run jobs/system/traefik.nomad.hcl

# Watch status
watch nomad job status traefik

# Check allocation health
nomad alloc status $(nomad job allocs traefik | grep running | head -1 | awk '{print $1}')

# Verify Traefik is serving
curl -f http://traefik.lab.hartr.net || echo "❌ Traefik not accessible"

# Check logs for config loading
nomad alloc logs $(nomad job allocs traefik | grep running | head -1 | awk '{print $1}') | grep -i "configuration loaded"
```

**Expected log line:**
```
Configuration loaded from file: /etc/traefik/traefik.yml
```

**If issues:**
- Check file exists: `ssh ubuntu@10.0.0.60 "cat /mnt/nas/configs/infrastructure/traefik/traefik.yml"`
- Check mount in container: `nomad alloc exec <alloc-id> cat /etc/traefik/traefik.yml`
- Review logs: `nomad alloc logs <alloc-id>`

#### 4b. Deploy Loki
```fish
nomad job run jobs/services/observability/loki/loki.nomad.hcl

# Wait for healthy
sleep 10

# Verify
curl -f http://10.0.0.60:3100/ready || echo "❌ Loki not ready"
curl -s http://10.0.0.60:3100/config | jq '.server.http_listen_port'
# Expected: 3100
```

**Success indicators:**
- `/ready` endpoint returns 200
- `/config` shows correct configuration

#### 4c. Deploy Prometheus
```fish
nomad job run jobs/services/observability/prometheus/prometheus.nomad.hcl

# Wait for healthy
sleep 10

# Verify config loaded
curl -s http://prometheus.home/api/v1/status/config | jq '.status'
# Expected: "success"

# Check targets
curl -s http://prometheus.home/api/v1/targets | jq '.data.activeTargets | length'
# Expected: > 0 (should have multiple targets)

# Verify scraping works
curl -s http://prometheus.home/api/v1/query?query=up | jq '.data.result | length'
# Expected: > 0 (should have "up" metrics from targets)
```

**Success indicators:**
- Config endpoint returns success
- Targets are discovered
- Metrics are being scraped

#### 4d. Deploy Grafana
```fish
nomad job run jobs/services/observability/grafana/grafana.nomad.hcl

# Wait for healthy
sleep 15

# Verify health
curl -f http://grafana.home/api/health || echo "❌ Grafana not healthy"

# Check datasources
curl -u admin:admin -s http://grafana.home/api/datasources | jq '.[].name'
# Expected: "Prometheus", "Loki"

# Verify Prometheus datasource works
curl -u admin:admin -s http://grafana.home/api/datasources/proxy/1/api/v1/query?query=up | jq '.status'
# Expected: "success"
```

**Success indicators:**
- Health endpoint returns OK
- Both datasources configured
- Can query Prometheus through datasource

#### 4e. Deploy Alertmanager
```fish
nomad job run jobs/services/observability/alertmanager/alertmanager.nomad.hcl

# Wait for healthy
sleep 10

# Verify
curl -f http://10.0.0.60:9093/-/healthy || echo "❌ Alertmanager not healthy"

# Check config loaded
curl -s http://10.0.0.60:9093/api/v2/status | jq '.config.original'
# Expected: Show config with receivers and routes
```

---

### Step 5: Integration Testing

#### Test 1: End-to-End Monitoring Stack
```fish
# 1. Verify Grafana can query Prometheus
curl -u admin:admin -s "http://grafana.home/api/datasources/proxy/1/api/v1/query?query=up{job='prometheus'}" | jq '.data.result[0].value[1]'
# Expected: "1" (Prometheus is up)

# 2. Verify Loki is receiving logs
curl -s "http://loki.service.consul:3100/loki/api/v1/query?query={job=\"host_logs\"}" | jq '.data.result | length'
# Expected: > 0 (if Alloy is running)

# 3. Check Prometheus scraping all targets
curl -s http://prometheus.home/api/v1/targets | jq '.data.activeTargets[] | select(.health=="down") | .labels.job'
# Expected: Empty (no down targets)
```

#### Test 2: Config Change Workflow
```fish
# 1. Make a small change to Prometheus config
# Edit configs/observability/prometheus/prometheus.yml
# Add a comment or change scrape_interval

# 2. Sync config
task configs:sync

# 3. Restart Prometheus
nomad job restart prometheus

# 4. Verify new config loaded
curl -s http://prometheus.home/api/v1/status/config | jq '.data.yaml' | grep -i "your-change"
# Expected: Should show your change
```

#### Test 3: Traefik Routing
```fish
# Verify all services accessible via Traefik
for service in prometheus grafana loki alertmanager; do
  echo "Testing $service..."
  curl -Iks https://$service.lab.hartr.net | head -1
done

# Expected: All should return "HTTP/2 200" or redirect to auth
```

---

## Troubleshooting

### Issue: Config file not found
**Symptoms:**
- Container fails to start
- Logs show "no such file or directory"

**Solutions:**
```fish
# 1. Verify file on NAS
ssh ubuntu@10.0.0.60 "ls -la /mnt/nas/configs/path/to/config.yml"

# 2. Check file permissions
ssh ubuntu@10.0.0.60 "stat /mnt/nas/configs/path/to/config.yml"
# Should be owned by nomad:nomad, mode 0644

# 3. Re-sync configs
task configs:sync

# 4. Check NFS mount
ssh ubuntu@10.0.0.60 "mount | grep /mnt/nas"
```

### Issue: Service won't start after config change
**Symptoms:**
- Job stuck in pending
- Container exits immediately

**Solutions:**
```fish
# 1. Check job validation
nomad job validate jobs/path/to/job.nomad.hcl

# 2. Check allocation events
nomad alloc status <alloc-id>

# 3. View container logs
nomad alloc logs <alloc-id>

# 4. Exec into container to debug
nomad alloc exec <alloc-id> /bin/sh
# Then check: cat /etc/service/config.yml
```

### Issue: Grafana datasources not loading
**Symptoms:**
- Datasources list is empty
- Can't query Prometheus from Grafana

**Solutions:**
```fish
# 1. Check datasources file
ssh ubuntu@10.0.0.60 "cat /mnt/nas/configs/observability/grafana/datasources.yml"

# 2. Check Grafana logs
nomad alloc logs <grafana-alloc-id> | grep -i datasource

# 3. Verify file is mounted in container
nomad alloc exec <grafana-alloc-id> cat /etc/grafana/provisioning/datasources/datasources.yml

# 4. Check provisioning directory
nomad alloc exec <grafana-alloc-id> ls -la /etc/grafana/provisioning/datasources/
```

### Issue: Prometheus targets not discovered
**Symptoms:**
- Targets page shows empty or missing targets
- Consul SD not working

**Solutions:**
```fish
# 1. Check Prometheus config
curl -s http://prometheus.home/api/v1/status/config | jq '.data.yaml'

# 2. Verify Consul is accessible from Prometheus container
nomad alloc exec <prom-alloc-id> nc -zv localhost 8500

# 3. Check Consul service registrations
consul catalog services
consul catalog nodes -service=node-exporter

# 4. Review Prometheus service discovery page
# Navigate to: http://prometheus.home/service-discovery
```

---

## Success Criteria

### ✅ Phase 1 Complete When:
- [ ] All 5 services deployed successfully
- [ ] Config files loading from `/mnt/nas/configs/`
- [ ] Grafana shows Prometheus and Loki datasources
- [ ] Prometheus scraping all configured targets
- [ ] Alertmanager config loaded correctly
- [ ] Traefik routing to all services works
- [ ] Can modify config, sync, restart, and see changes
- [ ] No errors in service logs related to config loading

### 📊 Validation Commands
```fish
# Quick health check
task test:services

# Detailed status
nomad job status traefik | grep -E "(Status|Healthy)"
nomad job status prometheus | grep -E "(Status|Healthy)"
nomad job status grafana | grep -E "(Status|Healthy)"
nomad job status loki | grep -E "(Status|Healthy)"
nomad job status alertmanager | grep -E "(Status|Healthy)"
```

---

## Rollback Plan

If critical issues occur:

```fish
# 1. Stop using external configs (revert job files)
git checkout HEAD~1 jobs/system/traefik.nomad.hcl
git checkout HEAD~1 jobs/services/observability/prometheus/prometheus.nomad.hcl
git checkout HEAD~1 jobs/services/observability/grafana/grafana.nomad.hcl
git checkout HEAD~1 jobs/services/observability/loki/loki.nomad.hcl
git checkout HEAD~1 jobs/services/observability/alertmanager/alertmanager.nomad.hcl

# 2. Redeploy with old configs
nomad job run jobs/system/traefik.nomad.hcl
nomad job run jobs/services/observability/prometheus/prometheus.nomad.hcl
nomad job run jobs/services/observability/grafana/grafana.nomad.hcl
nomad job run jobs/services/observability/loki/loki.nomad.hcl
nomad job run jobs/services/observability/alertmanager/alertmanager.nomad.hcl

# 3. Verify services recover
task test:services
```

---

## Next Steps After Testing

**If tests pass:** Move to Phase 1B (extract more configs)  
**If issues found:** Document problems, fix, re-test  
**When confident:** Continue to Phase 2 (database consolidation)

---

**Testing Date:** _________________  
**Tested By:** _________________  
**Results:** ✅ Pass / ❌ Fail  
**Notes:** _________________________
