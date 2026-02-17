# Phase 1 - Config Externalization

**Last Updated**: February 15, 2026  
**Project Duration**: February 11, 2026  
**Status**: ✅ Complete - All services deployed successfully

## Overview

Phase 1 validated the **config externalization pattern** for the homelab by migrating 5 observability services from embedded HEREDOC configs to external YAML files on NFS storage.

**Goal**: Reduce Nomad job file complexity and improve config maintainability by externalizing static configurations.

**Result**: ✅ Pattern validated successfully across all services

**Services Migrated:**
- ✅ Traefik (infrastructure/reverse proxy)
- ✅ Loki (log aggregation)
- ✅ Prometheus (metrics collection)
- ✅ Grafana (visualization)
- ✅ Alertmanager (alert routing)

**Impact:**
- **265+ lines** of embedded HCL configs removed from job files
- **17 new files** created (configs + automation)
- **Config changes** now take ~2 minutes (down from ~5 minutes)
- **Troubleshooting** easier with direct file access vs log parsing

---

## Architecture

### Before: Embedded Configs (Anti-Pattern)

```hcl
job "prometheus" {
  task "server" {
    template {
      destination = "local/prometheus.yml"
      data = <<EOH
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
  
  # ... 100+ more lines ...
EOH
    }
  }
}
```

**Problems:**
- Config mixed with infrastructure code
- Hard to validate (no YAML syntax checking)
- Difficult to diff/review changes
- Can't use YAML tools (yamllint, editors)
- Long job files (400+ lines common)

### After: External Configs (Pattern)

**Job file (clean):**
```hcl
job "prometheus" {
  group "monitoring" {
    volume "config" {
      type      = "host"
      source    = "prometheus_config"
      read_only = true
    }
    
    task "server" {
      volume_mount {
        volume      = "config"
        destination = "/etc/prometheus"
      }
      
      config {
        image = "prom/prometheus:latest"
        args  = ["--config.file=/etc/prometheus/prometheus.yml"]
      }
    }
  }
}
```

**External config:**
```yaml
# configs/observability/prometheus/prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    consul_sd_configs:
      - server: 'localhost:8500'
```

**Benefits:**
- ✅ Separation of concerns (infra vs config)
- ✅ YAML validation with standard tools
- ✅ Easy to edit with proper syntax highlighting
- ✅ Can validate before deployment
- ✅ Job files reduced to ~100 lines

### Config Storage Strategy

**NFS Mount:**
- **Location**: `/mnt/nas/configs/` on all Nomad clients
- **Ownership**: `nomad:nomad` (group-writable for automation)
- **Sync**: Ansible `config-sync` role via `task configs:sync`

**Directory Structure:**
```
/mnt/nas/configs/
├── infrastructure/
│   └── traefik/
│       └── traefik.yml
├── observability/
│   ├── alertmanager/
│   │   └── alertmanager.yml
│   ├── grafana/
│   │   ├── dashboards.yml
│   │   └── datasources.yml
│   ├── loki/
│   │   └── loki.yaml
│   └── prometheus/
│       └── prometheus.yml
└── auth/
    └── (future: Authelia configs)
```

**Nomad Host Volumes:**
```hcl
# Defined in ansible/roles/nomad-client/templates/nomad.hcl.j2
host_volume "prometheus_config" {
  path      = "/mnt/nas/configs/observability/prometheus"
  read_only = true
}

host_volume "grafana_config" {
  path      = "/mnt/nas/configs/observability/grafana"
  read_only = true
}

# ... etc for other services
```

### Hybrid Pattern for Secrets

Some services still need **templated configs** for dynamic values (Vault secrets, Consul service discovery):

**Example: Grafana Datasources**
```hcl
# External base config: datasources.yml
template {
  destination = "local/db.env"
  env         = true
  data        = <<EOH
DB_PASSWORD={{ with secret "secret/data/postgres/grafana" }}{{ .Data.data.password }}{{ end }}
EOH
}
```

**When to use each:**
- **External config**: Static configuration (scrape intervals, routes, receivers)
- **Vault template**: Secrets (passwords, API keys, tokens)
- **Consul template**: Dynamic service discovery (backends, upstreams)

---

## Issues Encountered & Solutions

### 1. Ansible `become` Privilege Escalation Issue

**Problem:**
```
[ERROR]: Premature end of stream waiting for become success.
sudo: a password is required
```

**Root Cause:**
- Global `become = True` in `ansible.cfg` applies to ALL tasks
- `synchronize` task with `delegate_to: localhost` tried to run `sudo` on Mac
- macOS requires password for sudo

**Solution:**
```yaml
# ansible/roles/config-sync/tasks/main.yml
- name: Sync all config files
  synchronize:
    src: "{{ playbook_dir }}/../../configs/"
    dest: "/mnt/nas/configs/"
  delegate_to: localhost
  become: no  # <-- Explicitly disable for localhost tasks
```

**Lesson**: Always set `become: no` for delegated localhost tasks when global `become` is enabled.

---

### 2. Missing `rsync` on Nomad Clients

**Problem:**
```
bash: rsync: command not found
```

**Root Cause:**
- Packer templates don't include `rsync` by default
- Ansible `synchronize` module requires `rsync` on both ends
- Debian cloud images don't have it pre-installed

**Immediate Solution:**
```fish
# Install on each client
for ip in 10.0.0.60 10.0.0.61 10.0.0.62 10.0.0.63 10.0.0.64 10.0.0.65
  ssh ubuntu@$ip "sudo apt-get update && sudo apt-get install -y rsync"
end
```

**Permanent Solution:**
Add to `ansible/roles/base-system/tasks/main.yml`:
```yaml
- name: Install essential utilities
  apt:
    name:
      - rsync
      - tree
      - htop
    state: present
  become: yes
```

**Lesson**: Document package dependencies for Ansible modules. Add to base system role for future VM builds.

---

### 3. NFS Permission Issues

**Problem:**
```
rsync: failed to set times on "/mnt/nas/configs/.": Operation not permitted
rsync: failed to set permissions on "/mnt/nas/configs/auth": Operation not permitted
```

**Root Cause:**
- `/mnt/nas/configs` owned by `nomad:nomad` with `755` permissions
- `ubuntu` user not in `nomad` group
- `rsync --archive` tries to preserve permissions/timestamps/ownership (NFS doesn't support all operations)

**Solution (User Groups):**
```fish
# Add ubuntu to nomad group
for ip in 10.0.0.60 10.0.0.61 10.0.0.62 10.0.0.63 10.0.0.64 10.0.0.65
  ssh ubuntu@$ip "sudo usermod -a -G nomad ubuntu"
end

# Verify
ssh ubuntu@10.0.0.60 "groups ubuntu"
# Output: ubuntu adm dialout cdrom sudo nomad
```

**Solution (Directory Permissions):**
```fish
# Make configs directory group-writable
ssh ubuntu@10.0.0.60 "sudo chmod 775 /mnt/nas/configs"
ssh ubuntu@10.0.0.60 "sudo chmod -R 775 /mnt/nas/configs/*"
```

**Solution (rsync Flags):**
```yaml
# ansible/roles/config-sync/tasks/main.yml
rsync_opts:
  - "--exclude=.git"
  - "--exclude=README.md"
  - "--omit-dir-times"    # Don't set directory timestamps
  - "--no-perms"          # Don't preserve permissions
  - "--no-owner"          # Don't preserve ownership
  - "--no-group"          # Don't preserve group
```

**Lesson**: NFS has stricter permission requirements. Use group membership + simplified rsync flags instead of full archive mode.

---

### 4. Ansible Role Path Resolution

**Problem:**
```
[ERROR]: the role 'config-sync' was not found
```

**Root Cause:**
- Playbook in `ansible/playbooks/sync-configs.yml`
- Role in `ansible/roles/config-sync/`
- Ansible looks for roles relative to playbook location

**Solution:**
```yaml
# ansible/playbooks/sync-configs.yml
roles:
  - role: ../roles/config-sync  # Relative path from playbook
```

**Alternative:** Update `ansible.cfg`:
```ini
[defaults]
roles_path = roles:../roles
```

**Lesson**: Use relative paths `../roles/` when playbooks are in subdirectories, or configure `roles_path` globally.

---

### 5. Loki Structured Metadata Schema Mismatch

**Problem:**
```
level=error msg="validating config" err="schema v13 required for structured metadata,
your schema version is v11"
```

**Root Cause:**
- Loki 3.6.0 defaults to structured metadata enabled
- Homelab using older schema v11 with `boltdb-shipper`
- Structured metadata requires schema v13 + `tsdb` index
- Storage schema upgrade requires data migration

**Solution:**
```yaml
# configs/observability/loki/loki.yaml
limits_config:
  reject_old_samples: true
  reject_old_samples_max_age: 168h
  allow_structured_metadata: false  # Disable until schema v13
```

**Important**: Job required **full purge** before redeployment:
```fish
nomad job stop -purge loki  # Complete removal
nomad job run jobs/services/observability/loki/loki.nomad.hcl
```

**Why purge was necessary:**
- `nomad job stop` + `nomad job run` kept old failed allocations
- Deployment showed "cancelled because job is stopped"
- `-purge` flag removes all job state for fresh start

**Lesson**: 
- Check version compatibility with existing storage schemas
- Container defaults may need explicit disabling
- Use `nomad job stop -purge` for problematic stuck jobs

---

## Deployment Results

### Services Successfully Migrated

| Service | Status | Config Location | Lines Externalized | Notes |
|---------|--------|----------------|-------------------|-------|
| **Traefik** | ✅ Healthy | `/mnt/nas/configs/infrastructure/traefik/traefik.yml` | ~55 | Static config external, dynamic Authelia still templated |
| **Loki** | ✅ Healthy | `/mnt/nas/configs/observability/loki/loki.yaml` | ~50 | Required `allow_structured_metadata: false` |
| **Prometheus** | ✅ Healthy | `/mnt/nas/configs/observability/prometheus/prometheus.yml` | ~100 | Consul SD works with external config |
| **Grafana** | ✅ Healthy | `/mnt/nas/configs/observability/grafana/{datasources,dashboards}.yml` | ~15 | Hybrid: external + Vault template for DB |
| **Alertmanager** | ✅ Healthy | `/mnt/nas/configs/observability/alertmanager/alertmanager.yml` | ~45 | Full externalization |

**Total**: 265+ lines of HEREDOC removed from job files

### Verification Commands

**Traefik:**
```fish
curl -s http://10.0.0.60:8080/api/overview | jq '.providers'
# Expected: ["File","ConsulCatalog"]
```

**Loki:**
```fish
curl -s http://10.0.0.60:3100/ready
# Expected: HTTP 200
```

**Prometheus:**
```fish
curl -s http://prometheus.home/api/v1/status/config | jq '.status'
# Expected: "success"

curl -s http://prometheus.home/api/v1/targets | jq '.data.activeTargets | length'
# Expected: > 0
```

**Grafana:**
```fish
curl -f http://grafana.home/api/health
# Expected: HTTP 200

curl -u admin:admin -s http://grafana.home/api/datasources | jq '.[].name'
# Expected: "Prometheus", "Loki"
```

**Alertmanager:**
```fish
curl -f http://10.0.0.60:9093/-/healthy
# Expected: HTTP 200
```

---

## Config Sync Workflow

### Making Config Changes

**1. Edit config files locally:**
```fish
vim configs/observability/prometheus/prometheus.yml
```

**2. Sync to cluster:**
```fish
task configs:sync
```

**3. Restart affected service:**
```fish
nomad job run jobs/services/observability/prometheus/prometheus.nomad.hcl
```

### Ansible Role (`config-sync`)

The `config-sync` role handles:
- ✅ Creates directory structure on NAS
- ✅ Syncs files from repo to `/mnt/nas/configs/`
- ✅ Works without sudo (group permissions)
- ✅ Handles NFS limitations gracefully

**Usage:**
```fish
# Via Taskfile
task configs:sync

# Direct Ansible
cd ansible && ansible-playbook playbooks/sync-configs.yml
```

---

## Testing Procedures

### Pre-Flight Checklist

Before deploying config changes:

```fish
# 1. Validate locally
task validate:all

# 2. Check cluster health
nomad node status
consul members

# 3. Verify NAS mount
ssh ubuntu@10.0.0.60 "ls -la /mnt/nas/configs/"
```

### Deployment Process (Incremental)

**Deploy one service at a time to catch issues early:**

#### Step 1: Sync Configs
```fish
task configs:sync

# Verify files synced
ssh ubuntu@10.0.0.60 "tree /mnt/nas/configs/"
```

#### Step 2: Validate Job Files
```fish
nomad job validate jobs/system/traefik.nomad.hcl
nomad job validate jobs/services/observability/prometheus/prometheus.nomad.hcl
nomad job validate jobs/services/observability/grafana/grafana.nomad.hcl
nomad job validate jobs/services/observability/loki/loki.nomad.hcl
nomad job validate jobs/services/observability/alertmanager/alertmanager.nomad.hcl
```

#### Step 3: Deploy Services
```fish
# Deploy
nomad job run jobs/system/traefik.nomad.hcl

# Watch status
watch nomad job status traefik

# Check logs for config loading
ALLOC_ID=$(nomad job allocs traefik | grep running | head -1 | awk '{print $1}')
nomad alloc logs $ALLOC_ID | grep -i "configuration loaded"
```

### Integration Testing

**Test 1: End-to-End Monitoring Stack**
```fish
# Verify Grafana → Prometheus connection
curl -u admin:admin -s "http://grafana.home/api/datasources/proxy/1/api/v1/query?query=up{job='prometheus'}" | jq '.data.result[0].value[1]'
# Expected: "1"

# Check Prometheus targets
curl -s http://prometheus.home/api/v1/targets | jq '.data.activeTargets[] | select(.health=="down") | .labels.job'
# Expected: Empty (no down targets)
```

**Test 2: Config Change Workflow**
```fish
# 1. Edit config
vim configs/observability/prometheus/prometheus.yml

# 2. Sync
task configs:sync

# 3. Restart
nomad job restart prometheus

# 4. Verify change loaded
curl -s http://prometheus.home/api/v1/status/config | jq '.data.yaml'
```

**Test 3: Traefik Routing**
```fish
for service in prometheus grafana loki alertmanager
  curl -Iks https://$service.lab.hartr.net | head -1
end
# Expected: All return "HTTP/2 200" or redirect
```

---

## Troubleshooting

### Config File Not Found

**Symptoms:**
- Container fails to start
- Logs show "no such file or directory"

**Diagnosis:**
```fish
# 1. Verify file on NAS
ssh ubuntu@10.0.0.60 "ls -la /mnt/nas/configs/observability/prometheus/prometheus.yml"

# 2. Check permissions
ssh ubuntu@10.0.0.60 "stat /mnt/nas/configs/observability/prometheus/prometheus.yml"
# Should be: nomad:nomad, mode 0644

# 3. Check NFS mount
ssh ubuntu@10.0.0.60 "mount | grep /mnt/nas"
```

**Solutions:**
```fish
# Re-sync configs
task configs:sync

# If mount missing, remount NFS
ssh ubuntu@10.0.0.60 "sudo mount -a"
```

---

### Service Won't Start After Config Change

**Symptoms:**
- Job stuck in pending
- Container exits immediately

**Diagnosis:**
```fish
# 1. Check job validation
nomad job validate jobs/services/observability/prometheus/prometheus.nomad.hcl

# 2. Check allocation events
ALLOC_ID=$(nomad job allocs prometheus | grep -v complete | head -1 | awk '{print $1}')
nomad alloc status $ALLOC_ID

# 3. View container logs
nomad alloc logs $ALLOC_ID
```

**Solutions:**
```fish
# Exec into container to debug
nomad alloc exec $ALLOC_ID /bin/sh
# Then: cat /etc/prometheus/prometheus.yml

# Validate config manually
promtool check config /path/to/prometheus.yml
```

---

### Grafana Datasources Not Loading

**Symptoms:**
- Datasources list empty
- Can't query Prometheus

**Diagnosis:**
```fish
# 1. Check datasources file
ssh ubuntu@10.0.0.60 "cat /mnt/nas/configs/observability/grafana/datasources.yml"

# 2. Check Grafana logs
ALLOC_ID=$(nomad job allocs grafana | grep running | head -1 | awk '{print $1}')
nomad alloc logs $ALLOC_ID | grep -i datasource

# 3. Verify mount in container
nomad alloc exec $ALLOC_ID cat /etc/grafana/provisioning/datasources/datasources.yml
```

**Solutions:**
```fish
# Check provisioning directory
nomad alloc exec $ALLOC_ID ls -la /etc/grafana/provisioning/datasources/

# Restart Grafana
nomad job restart grafana
```

---

### Prometheus Targets Not Discovered

**Symptoms:**
- Targets page empty
- Consul SD not working

**Diagnosis:**
```fish
# 1. Check Prometheus config
curl -s http://prometheus.home/api/v1/status/config | jq '.data.yaml'

# 2. Verify Consul accessible
ALLOC_ID=$(nomad job allocs prometheus | grep running | head -1 | awk '{print $1}')
nomad alloc exec $ALLOC_ID nc -zv localhost 8500

# 3. Check Consul registrations
consul catalog services
consul catalog nodes -service=node-exporter
```

**Solutions:**
```fish
# Check service discovery page
# Navigate to: http://prometheus.home/service-discovery

# Verify scrape config syntax
promtool check config configs/observability/prometheus/prometheus.yml
```

---

### rsync Permission Errors

**Symptoms:**
```
rsync: failed to set times: Operation not permitted
```

**Solutions:**
```fish
# 1. Verify ubuntu in nomad group
ssh ubuntu@10.0.0.60 "groups ubuntu | grep nomad"

# 2. Add if missing
ssh ubuntu@10.0.0.60 "sudo usermod -a -G nomad ubuntu"

# 3. Fix directory permissions
ssh ubuntu@10.0.0.60 "sudo chmod 775 /mnt/nas/configs"
ssh ubuntu@10.0.0.60 "sudo chmod -R 775 /mnt/nas/configs/*"

# 4. Re-login SSH session (for group to take effect)
```

---

## Success Criteria

### ✅ Phase 1 Complete When:
- [x] All 5 services deployed successfully
- [x] Config files loading from `/mnt/nas/configs/`
- [x] Grafana shows Prometheus and Loki datasources
- [x] Prometheus scraping all configured targets
- [x] Alertmanager config loaded correctly
- [x] Traefik routing to all services works
- [x] Can modify config, sync, restart, and see changes
- [x] No errors in service logs related to config loading

### Quick Health Check
```fish
task test:services

# Or manually:
for service in traefik prometheus grafana loki alertmanager
  nomad job status $service | grep -E "(Status|Healthy)"
end
```

---

## Rollback Plan

If critical issues occur:

```fish
# 1. Revert job files
git checkout HEAD~1 jobs/system/traefik.nomad.hcl
git checkout HEAD~1 jobs/services/observability/prometheus/prometheus.nomad.hcl
git checkout HEAD~1 jobs/services/observability/grafana/grafana.nomad.hcl
git checkout HEAD~1 jobs/services/observability/loki/loki.nomad.hcl
git checkout HEAD~1 jobs/services/observability/alertmanager/alertmanager.nomad.hcl

# 2. Redeploy with embedded configs
for job in jobs/system/traefik.nomad.hcl jobs/services/observability/*/*.nomad.hcl
  nomad job run $job
end

# 3. Verify recovery
task test:services
```

---

## Architecture Decisions Validated

### ✅ External Configs Work for Static Configuration
- Traefik static config loads successfully
- Prometheus scrape configs work from external files
- Loki configuration loads correctly
- No performance impact observed

### ✅ Hybrid Pattern Works for Secrets
- Grafana: External datasources.yml + Vault template for DB password
- Pattern allows security without sacrificing maintainability
- Can externalize most config, template only dynamic values

### ✅ NFS Storage Suitable for Configs
- **Read performance**: Excellent (configs cached by containers)
- **Write performance**: Adequate for infrequent updates
- **Reliability**: Shared access works across all clients

### ✅ Ansible Automation Reliable
- Config sync via `synchronize` module works well
- Group permissions + simplified rsync flags handle NFS limitations
- Can be integrated into CI/CD pipelines

---

## Metrics & Impact

### Time Investment
- **Planning**: ~2 hours (template creation, role design)
- **Implementation**: ~3 hours (file extraction, testing)
- **Troubleshooting**: ~1.5 hours (Ansible/rsync/permissions)
- **Total**: ~6.5 hours for 5 services

### Code Quality Improvements
- **Lines Reduced**: 265+ embedded config lines removed
- **Files Created**: 17 new files (configs + automation)
- **Maintainability**: ⬆️ Configs easier to edit, validate, version
- **Config Change Time**: 5 min → 2 min (60% faster)

### Future Efficiency Gains
- **Next 5 services**: Estimated 2-3 hours (pattern established)
- **Troubleshooting**: Easier with direct file access vs log parsing
- **Validation**: Can use standard YAML tools (yamllint, promtool)

---

## Recommendations for Future Work

### 1. Update Base System Role
Add to `ansible/roles/base-system/`:
```yaml
- name: Install utilities for config management
  apt:
    name:
      - rsync
      - tree
    state: present
```

### 2. Add Pre-Flight Checks
Update validation scripts:
```fish
# Check rsync on all clients
for ip in 10.0.0.60 10.0.0.61 10.0.0.62 10.0.0.63 10.0.0.64 10.0.0.65
  ssh ubuntu@$ip "which rsync" || echo "❌ rsync missing on $ip"
end

# Check ubuntu in nomad group
for ip in 10.0.0.60 10.0.0.61 10.0.0.62 10.0.0.63 10.0.0.64 10.0.0.65
  ssh ubuntu@$ip "groups ubuntu | grep nomad" || echo "❌ not in nomad group on $ip"
end
```

### 3. Pattern for New Services
**When externalizing configs:**
1. Create config file in `/configs/<category>/<service>/`
2. Add directory to `config-sync` role if new category
3. Update job file: replace HEREDOC with volume mount
4. Add host volume to Nomad client config
5. Run `task configs:sync`
6. Deploy with `nomad job run`

### 4. Consider Config Validation
Add pre-sync validation:
```fish
# Validate YAML syntax
yamllint configs/**/*.yml

# Service-specific validation
promtool check config configs/observability/prometheus/prometheus.yml
```

### 5. Document Hybrid Patterns
Services needing both external config + templates:
- **Authelia**: External `configuration.yml` + templated Vault secrets + Consul SD
- **Grafana**: External datasources + templated DB password
- **Traefik**: External static config + templated dynamic config (Authelia middleware)

---

## Next Steps

### Phase 1B - Continue Externalization
- [ ] Extract Homepage configs (already external, just document)
- [ ] Extract remaining service configs
- [ ] Add config validation to CI/CD

### Phase 2 - Database Consolidation
- [ ] Migrate services to dedicated databases (see [POSTGRESQL.md](POSTGRESQL.md))
- [ ] Remove shared database anti-pattern

### Phase 3 - Vault Integration
- [ ] Externalize Vault policies
- [ ] Automate Vault secret rotation
- [ ] Document secret management patterns

---

## Related Documentation

- [NEW_SERVICES_DEPLOYMENT.md](NEW_SERVICES_DEPLOYMENT.md) - Service deployment patterns
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - General troubleshooting guide
- [VAULT.md](VAULT.md) - Vault integration for secrets
- [POSTGRESQL.md](POSTGRESQL.md) - Database management (anti-pattern guide)

---

**Phase 1 Status**: ✅ **COMPLETE**  
**Pattern Validated**: External configs work reliably across all services  
**Recommendation**: Proceed with Phase 1B (expand to more services)
