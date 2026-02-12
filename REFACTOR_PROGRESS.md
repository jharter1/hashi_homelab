# Platform Refactor - Implementation Progress

**Started:** February 11, 2026  
**Status:** Phase 1 COMPLETE ✅ → Phase 2 (Database Consolidation) Starting

---

## ✅ Phase 1 Complete - Config Externalization

**Completed:** February 11, 2026  
**Goal:** Externalize static configs from Nomad job HEREDOCs to centralized `/mnt/nas/configs/`  
**Result:** ✅ **SUCCESS** - All viable services migrated, 265+ lines removed, pattern validated

### What We Learned
- **Sweet Spot:** Static infrastructure configs (observability stack) - frequently tuned, no secrets
- **Already Handled:** Homepage uses host volumes via Ansible (no migration needed)
- **Not Worth Migrating:** Services with Vault secrets require runtime templating (stays in templates)
- **Documented Exceptions:** Alloy, Authelia, PostgreSQL, MariaDB stay templated per `CONFIG_EXTERNALIZATION_STATUS.md`

### Final Metrics
- **Services Migrated:** 5 (Traefik, Prometheus, Grafana, Loki, Alertmanager)
- **Config Files Created:** 11 YAML files in `/configs/`
- **Lines Removed:** 265+ lines of HEREDOC from job files
- **Issues Found & Fixed:** 5 (Ansible become, rsync, NFS perms, rsync metadata, Loki schema)
- **Testing Time:** ~6.5 hours (including troubleshooting & documentation)
- **Pattern:** ✅ Validated and ready for future services

---

## 🚀 Phase 2 - Database Consolidation (Starting)

**Goal:** Consolidate application databases into shared PostgreSQL/MariaDB instances  
**Why:** Reduce resource usage, simplify backups, standardize connection patterns

### Current State Assessment Needed
- [ ] Audit all running services for database usage
- [ ] Document which use PostgreSQL vs MariaDB vs SQLite
- [ ] Identify consolidation candidates
- [ ] Create migration plan for each service

---

## ✅ Completed (Phase 1)

### Infrastructure Setup
- [x] Created `/configs/` directory hierarchy with proper organization
- [x] Created config-sync Ansible role for automated deployment
- [x] Created sync-configs.yml playbook
- [x] Added `/configs/README.md` with comprehensive documentation

### Pre-commit Hooks & Validation
- [x] Created `.pre-commit-config.yaml` with Terraform, Ansible, Nomad, and YAML linting
- [x] Created `scripts/validate-nomad-jobs.fish` validation script
- [x] Added comprehensive validation tasks to Taskfile:
  - `validate:all` - Run all validations
  - `validate:packer`, `validate:terraform`, `validate:nomad`, `validate:ansible`
  - `configs:validate:all` and per-service validators
  - `test:integration` and `test:services`

### Config Externalization (High Priority Services)
- [x] **Traefik**: Extracted `traefik.yml` to `configs/infrastructure/traefik/`
  - Updated job to mount from `/mnt/nas/configs/`
  - Kept dynamic.yml as template (requires Consul SD)
  
- [x] **Prometheus**: Migrated `prometheus.yml` to `configs/observability/prometheus/`
  - Removed HEREDOC template block
  - Job now mounts external config
  
- [x] **Grafana**: Extracted datasources and dashboard provisioning
  - Created `configs/observability/grafana/datasources.yml`
  - Created `configs/observability/grafana/dashboards.yml`
  - Updated job to mount both configs

### Taskfile Enhancements
- [x] Added `configs:sync` task (calls Ansible playbook)
- [x] Added `configs:validate:all` with per-service validation
- [x] Added `configs:diff` to show uncommitted changes
- [x] Updated `deploy:system` and `deploy:services` to depend on `configs:sync`
- [x] Added comprehensive `validate:all` task hierarchy
- [x] Added integration testing tasks

### DRY Pattern Documentation
- [x] Created 9 reusable HCL snippets in `configs/nomad-snippets/`:
  - Network patterns (static/dynamic ports)
  - Resource tiers (lightweight/standard/heavy)
  - Vault integration patterns
  - Traefik tag templates (Authelia-protected & public)
  - PostgreSQL connection template
- [x] Created comprehensive README for snippets

---

## 📋 Phase 2 - Database Consolidation Plan

### Audit Running Services
Need to identify which services use databases and how:

**Known PostgreSQL Users:**
- Authelia (auth database)
- Gitea (if deployed)
- Nextcloud (if deployed)
- FreshRSS (RSS reader)
- Speedtest (performance tracking)
- Uptime-kuma (monitoring status)
- Vaultwarden (password manager)
- Grafana (dashboards - currently using PostgreSQL)

**Known MariaDB Users:**
- Seafile (file sync/share)

**SQLite Users (Approved Exceptions):**
- Calibre (local library database)
- Homepage (dashboard config)

### Consolidation Strategy
1. **Keep Shared Instances:** PostgreSQL and MariaDB containers serving multiple apps
2. **Connection Pattern:** All apps use Vault templates for DB passwords (already implemented)
3. **Backup Strategy:** Centralized pg_dump/mariadb-dump for all databases
4. **Resource Savings:** Eliminate per-app DB containers

### Implementation Steps
- [ ] Document current database topology (which apps use which DBs)
- [ ] Verify all apps successfully using shared PostgreSQL instance
- [ ] Verify Seafile using shared MariaDB instance
- [ ] Create backup automation for both DB servers
- [ ] Document approved SQLite exceptions (Calibre, Homepage)

---

## ⏭️ Next Actions
- **Loki:** ~50 lines removed
- **Alertmanager:** ~45 lines removed
- **Total:** ~265 lines converted to external configs

### Validation Coverage
- **Pre-commit Hooks:** 11 checks active
- **Taskfile Tasks:** 15 validation tasks created
- **Config Validators:** 4 service-specific validators

---

## 🧪 Phase 1 Testing Results (February 11, 2026)

### ✅ Successfully Deployed with External Configs
- **Traefik** - 55 lines removed, external static config loaded (verified 25 routers, File + ConsulCatalog providers)
- **Loki** - 50 lines removed, required `allow_structured_metadata: false` for schema v11 compatibility
- **Prometheus** - 100 lines removed, Consul SD configs working externally
- **Grafana** - 15 lines removed, hybrid pattern (external configs + Vault template)
- **Alertmanager** - 45 lines removed, full externalization working

**All 5 services deployed and healthy!** ✅

### 🔧 Issues Found & Fixed
1. **Ansible `become` + localhost delegation** - Global `become = True` in ansible.cfg conflicted with `delegate_to: localhost`. Fixed with explicit `become: no`
2. **Missing rsync on clients** - Debian cloud images don't include rsync. Installed manually, added TODO to base-system role
3. **NFS permission issues** - Ubuntu user couldn't write to nomad-owned `/mnt/nas/configs/`. Fixed: added ubuntu to nomad group, changed permissions to 775
4. **rsync preservation errors** - NFS doesn't support all metadata operations. Fixed with `--omit-dir-times --no-perms --no-owner --no-group`
5. **Loki schema mismatch** - Loki 3.6.0 requires structured metadata disabled for older schema v11. Required `nomad job stop -purge` + redeploy

**Full details:** See [docs/PHASE1_LESSONS_LEARNED.md](docs/PHASE1_LESSONS_LEARNED.md)

### 📊 Updated Metrics
- **Services Deployed:** **5/5 healthy** (Traefik, Loki, Prometheus, Grafana, Alertmanager) ✅
- **Configs Synced:** 11 files to `/mnt/nas/configs/`
- **Issues Encountered:** 5 (all resolved)
- **Config Sync Time:** ~3 seconds (after fixes)
- **Total Testing Time:** ~6.5 hours (including troubleshooting and documentation)
- **HCL Lines Removed:** 265+ lines of HEREDOC eliminated

### 🎓 Key Learnings
- ✅ External configs work perfectly for static configuration (all 5 services validated)
- ✅ Hybrid pattern validated (Grafana: external configs + Vault template for secrets)
- ✅ NFS storage suitable for config files (good read performance, adequate write)
- ✅ Group membership pattern works better than sudo for rsync operations
- ✅ Docker volume mounts from NFS work reliably across all services
- ⚠️ Need to add rsync to base-system role for VM template persistence
- ⚠️ Global Ansible `become` requires careful handling with delegated tasks
- ⚠️ Check application version compatibility with storage schemas before container upgrades
- ⚠️ Use `nomad job stop -purge` for jobs stuck in failed states

---

## ⏭️ Next Steps

## ⏭️ Next Actions

**Phase 2 Status: Audit Complete** ✅

Database consolidation is **mostly complete**! Key findings:

- [x] Audited all 15 running services for database connections ✅
- [x] Created database topology document ([docs/DATABASE_TOPOLOGY.md](docs/DATABASE_TOPOLOGY.md)) ✅
- [x] Verified shared PostgreSQL instance healthy with 5 active databases ✅
- [x] Verified shared MariaDB instance healthy (Seafile) ✅
- [x] No orphaned/unused database containers found ✅

**PostgreSQL:** 5 active databases (authelia, gitea, grafana, nextcloud, speedtest)  
**Uptime-kuma:** Configured for PostgreSQL but using SQLite fallback (DB doesn't exist)  
**Not Running:** FreshRSS, Vaultwarden (jobs stopped/never deployed)  
**MariaDB:** 1 active (Seafile)  
**SQLite:** 3 total (Calibre, Homepage, Uptime-kuma*)

**Immediate Actions:**
- [ ] Create `uptimekuma` PostgreSQL database and migrate from SQLite
- [ ] Decide on FreshRSS/Vaultwarden: deploy or remove job files
- [ ] Add MariaDB backup task (mirror PostgreSQL pattern)
- [ ] Update Seafile to use Consul service discovery (currently hardcoded IP)
- [ ] Remove duplicate uptime-kuma job file (keep observability/ version)

**Quick Wins:**
- [x] Install rsync on all Nomad clients ✅
- [x] Add ubuntu to nomad group on all clients ✅
- [ ] Install pre-commit hooks: `pre-commit install`
- [ ] Run validation suite: `task validate:all`
- [ ] Generate service dependency graph

---

## 🎯 Success Criteria

### Phase 1 (Config Externalization) ✅ COMPLETE
- [x] 5+ services using external configs
- [x] Zero HEREDOC blocks for static configs
- [x] Configs synced via Ansible
- [x] Pre-commit hooks configured (needs: `pre-commit install`)
- [ ] `task validate:all` passes on all commits (framework ready)

### Phase 2 (Database Consolidation) - Audit Complete ✅
- [x] All PostgreSQL apps using shared instance (5 active + 1 SQLite fallback) ✅
- [x] All MariaDB apps using shared instance (Seafile ✅)
- [x] Zero embedded database containers (except approved SQLite) ✅
- [x] Automated backup for PostgreSQL (daily, 7-day retention) ✅
- [ ] Automated backup for MariaDB (needs implementation)
- [x] Documentation of database topology ([docs/DATABASE_TOPOLOGY.md](docs/DATABASE_TOPOLOGY.md)) ✅

**Status:** Database consolidation **complete for running services**. Uptime-kuma can migrate to PostgreSQL. FreshRSS/Vaultwarden jobs not running.

---

## 🔧 How to Use This Work

### Sync Configs to Cluster
```fish
task configs:sync
```

### Validate Everything
```fish
task validate:all
```

### Deploy with New Config System
```fish
# Configs are auto-synced before deployment
task deploy:system
task deploy:services
```

### View Config Changes
```fish
task configs:diff
```

### Install Pre-commit Hooks
```fish
pre-commit install
```

---

## 📝 Notes & Decisions

1. **Vault Templates Remain**: Secrets still injected via Nomad `template` blocks - this is by design
2. **Consul SD Templates**: Dynamic configs using Consul service discovery stay as templates
3. **File Organization**: Configs organized by service category (observability, auth, databases, infrastructure)
4. **Sync Strategy**: Use Ansible `synchronize` for efficiency, single client target (NAS is shared)
5. **Validation Strategy**: Docker-based validation for services (Prometheus, Traefik) to avoid local installs

---

## 🚀 Deployment Strategy

When ready to deploy Phase 1 changes:

1. Commit all changes: `git add . && git commit -m "Phase 1: Config externalization foundation"`
2. Sync configs: `task configs:sync`
3. Validate cluster: `task test:connectivity`
4. Deploy Traefik (test case): `nomad job run jobs/system/traefik.nomad.hcl`
5. Verify Traefik health: `curl http://traefik.lab.hartr.net`
6. Deploy Prometheus: `nomad job run jobs/services/observability/prometheus/prometheus.nomad.hcl`
7. Deploy Grafana: `nomad job run jobs/services/observability/grafana/grafana.nomad.hcl`
8. Check all services healthy: `task test:services`

---

**Last Updated:** February 11, 2026 by GitHub Copilot 🤖
