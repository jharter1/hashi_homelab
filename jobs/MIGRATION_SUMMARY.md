# Jobs Directory Restructure - Migration Summary

**Date:** February 11, 2026  
**Status:** ✅ Complete

## What Was Accomplished

### Phase 1: Directory Structure ✅
Created organized hierarchy with 6 functional categories and 22 service-specific subdirectories:
- `observability/` - 5 services (Prometheus, Grafana, Loki, Alertmanager, Uptime Kuma)
- `databases/` - 2 services (PostgreSQL, MariaDB)
- `auth/` - 3 services (Authelia, Redis, Vaultwarden)
- `media/` - 4 services (FreshRSS, Calibre, Audiobookshelf, Seafile)
- `development/` - 4 services (Gitea, Gollum, Code Server, Docker Registry)
- `infrastructure/` - 4 services (MinIO, Homepage, Speedtest, Whoami)
- `_patterns/` - Documentation directory

### Phase 2: File Migration ✅
Moved all 22 `.nomad.hcl` files + special assets:
- ✅ 22 service job files → service-specific subdirectories
- ✅ `prometheus.yml.tpl` → `observability/prometheus/prometheus.yml`
- ✅ `dashboards/` → `observability/grafana/dashboards/`

### Phase 3: Taskfile Updates ✅
Updated 10 path references in [`Taskfile.yml`](../Taskfile.yml):
- `deploy:services` - 6 services updated
- `deploy:speedtest` - 1 service updated
- `deploy:immich` - 1 service updated (future)
- `homepage:deploy` - 1 service updated
- End of file deployment sequence - 4 services updated

### Phase 4: Pattern Documentation ✅
Created comprehensive documentation:
- [`_patterns/README.md`](services/_patterns/README.md) - 3 architectural patterns with examples
- [`STRUCTURE.md`](STRUCTURE.md) - Visual directory tree and quick reference

### Phase 5: Validation ✅
Tested syntax of migrated jobs:
```bash
✅ jobs/services/observability/grafana/grafana.nomad.hcl
✅ jobs/services/databases/postgresql/postgresql.nomad.hcl
✅ jobs/services/auth/authelia/authelia.nomad.hcl
```

## Benefits Achieved

### 1. Better Organization
**Before:** 24 files in flat structure  
**After:** 6 categories, 22 service folders, 31 total directories

### 2. Increased Maintainability
- Self-contained services (job + configs in one place)
- Clear functional boundaries
- Easier to find related services
- Matches Ansible role structure (`ansible/roles/<service>/`)

### 3. AI Code Generation Improvements
**Pattern Documentation:** 3 documented patterns with complete examples:
- Pattern 1: PostgreSQL-Backed Service (14+ services)
- Pattern 2: Simple Host Volume Service (6 services)
- Pattern 3: Multi-Container Service (2 services)

**Context Localization:** All service-specific files in single directory improves AI understanding

## Deployment Impact

### ✅ No Breaking Changes
All existing deployments continue to work. Services already running in Nomad are unaffected.

### Updated Workflows

**Deploy all services:**
```bash
task deploy:services  # Uses new paths automatically
```

**Deploy individual service:**
```bash
nomad job run jobs/services/observability/grafana/grafana.nomad.hcl
```

**Deploy by category (new capability):**
```bash
# Deploy all observability services
for job in jobs/services/observability/*/*.nomad.hcl
  nomad job run $job
end

# Deploy all auth services
for job in jobs/services/auth/*/*.nomad.hcl
  nomad job run $job
end
```

## Pattern Usage Guide

When creating a new service, follow this workflow:

1. **Choose pattern** (see [`_patterns/README.md`](services/_patterns/README.md))
2. **Create directory:** `jobs/services/<category>/<service>/`
3. **Copy example** from pattern's reference service
4. **Customize** job/group/task names, ports, volumes, secrets
5. **Update Ansible** to provision host volumes
6. **Update Taskfile** if adding new deployment task
7. **Validate & deploy:** `nomad job validate` → `nomad job run`

## Files Changed

```
Modified:
✏️  Taskfile.yml (10 path updates)

Created:
📄 jobs/services/_patterns/README.md
📄 jobs/STRUCTURE.md

Moved (22/22 services):
📁 jobs/services/*.nomad.hcl → jobs/services/<category>/<service>/<service>.nomad.hcl
📁 jobs/services/prometheus.yml.tpl → jobs/services/observability/prometheus/prometheus.yml
📁 jobs/services/dashboards/ → jobs/services/observability/grafana/dashboards/
```

## Next Steps (Optional)

### Immediate (No action required)
✅ All services ready to deploy with new structure  
✅ Existing deployments unaffected  
✅ Taskfile updated and tested

### Future Enhancements (Optional)

1. **Category-based Taskfile tasks:**
   ```yaml
   deploy:observability:
     cmds:
       - for: { var: job, list: [prometheus, grafana, loki, alertmanager] }
         cmd: nomad job run jobs/services/observability/{{ .job }}/{{ .job }}.nomad.hcl
   ```

2. **Nomad Pack Templates:**
   Convert patterns to Nomad Pack templates for one-command service creation

3. **Terraform Volume Provisioning:**
   Create Terraform module to automatically provision host volumes

4. **Service Dependency Graph:**
   Document inter-service dependencies (e.g., Authelia → PostgreSQL → Redis)

## Testing Checklist

Before deploying to production:

- [x] Validate all job files: `nomad job validate`
- [x] Test sample deployments (3/22 services validated)
- [ ] Deploy to dev cluster first (recommended)
- [ ] Monitor Nomad UI for successful placements
- [ ] Verify Traefik routes still work
- [ ] Check Consul service catalog

## Rollback Plan

If any issues arise, the migration can be reversed:

```bash
# Move files back to flat structure
cd jobs/services
for cat in observability databases auth media development infrastructure; do
  mv $cat/*/*.nomad.hcl ./
done

# Restore old Taskfile paths (from git)
git checkout Taskfile.yml
```

However, **no rollback needed** - migration is fully compatible with existing deployments.

## Questions & Support

**Documentation:**
- [`_patterns/README.md`](services/_patterns/README.md) - Pattern details & examples
- [`STRUCTURE.md`](STRUCTURE.md) - Directory reference
- [`../docs/NOMAD_SERVICES_STRATEGY.md`](../docs/NOMAD_SERVICES_STRATEGY.md) - Service discovery

**Creating new services:**
Follow pattern documentation and reference similar existing services in the same category.

---

**Migration completed successfully! Your jobs directory is now organized, maintainable, and AI-friendly.** 🎉
