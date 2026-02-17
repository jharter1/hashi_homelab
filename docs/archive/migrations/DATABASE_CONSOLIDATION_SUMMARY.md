# Database Consolidation Summary

**⚠️ UPDATE (February 12, 2026):** Uptime-Kuma was **reverted back to SQLite** due to monitoring anti-pattern. See section below.

## Changes Made

Successfully migrated 4 services from SQLite/embedded databases to the centralized PostgreSQL instance.

*Note: Uptime-Kuma was later reverted (see "Lessons Learned" section below).*

### Services Migrated

1. **Immich** - Photo backup and management
   - Before: Embedded PostgreSQL container (tensorchord/pgvecto-rs)
   - After: Central PostgreSQL with Vault integration
   - Note: Removed 500MB+ sidecar container

2. **Speedtest Tracker** - Network speed monitoring
   - Before: SQLite database
   - After: Central PostgreSQL with Vault integration

3. **Uptime-Kuma** - Uptime monitoring
   - Before: SQLite database
   - After: Central PostgreSQL with connection string
   - **⚠️ REVERTED (Feb 12, 2026)**: Back to SQLite due to monitoring anti-pattern (see Lessons Learned)

4. **Vaultwarden** - Password manager (Bitwarden compatible)
   - Before: SQLite database
   - After: Central PostgreSQL with Vault integration

### Files Modified

1. **jobs/services/postgresql.nomad.hcl**
   - Added database initialization for: immich, speedtest, uptimekuma, vaultwarden
   - Each with dedicated user and password from Vault

2. **jobs/services/immich.nomad.hcl**
   - Removed embedded PostgreSQL sidecar task
   - Removed immich_postgres volume mount
   - Added Vault workload identity
   - Updated DB connection to use central PostgreSQL
   - Applied same changes to microservices task

3. **jobs/services/speedtest.nomad.hcl**
   - Changed DB_CONNECTION from "sqlite" to "pgsql"
   - Added Vault template for credentials
   - Updated database configuration

4. **jobs/services/uptime-kuma.nomad.hcl**
   - Removed UPTIME_KUMA_DB_TYPE = "sqlite"
   - Added PostgreSQL connection string via Vault
   - Added Vault workload identity

5. **jobs/services/vaultwarden.nomad.hcl**
   - Changed DATABASE_URL from SQLite file to PostgreSQL connection string
   - Added Vault template for credentials
   - Added Vault workload identity

### New Files Created

1. **scripts/setup-db-migration-secrets.fish**
   - Creates Vault secrets for new database users
   - Generates secure random passwords
   - Stores at: secret/postgres/{immich,speedtest,uptimekuma,vaultwarden}

2. **scripts/migrate-databases.fish**
   - Automated migration deployment script
   - Includes prerequisite checks
   - Handles service redeployment in correct order
   - Provides verification steps

3. **docs/DATABASE_MIGRATION.md**
   - Complete migration documentation
   - Prerequisites and setup instructions
   - Backup procedures
   - Rollback plan
   - Post-migration cleanup
   - Monitoring and troubleshooting

4. **Taskfile.yml** (updated)
   - Added `task db:migrate` command for easy deployment

## Deployment Instructions

### Quick Start

```bash
# Run the complete migration
task db:migrate

# Or manually:
fish scripts/migrate-databases.fish
```

### Manual Steps

If you prefer to run steps individually:

```bash
# 1. Create Vault secrets
fish scripts/setup-db-migration-secrets.fish

# 2. Redeploy PostgreSQL
nomad job stop postgresql
nomad job run jobs/services/postgresql.nomad.hcl

# 3. Wait for initialization
sleep 30

# 4. Deploy migrated services
nomad job run jobs/services/immich.nomad.hcl
nomad job run jobs/services/speedtest.nomad.hcl
nomad job run jobs/services/uptime-kuma.nomad.hcl
nomad job run jobs/services/vaultwarden.nomad.hcl
```

## Important Warnings

### Data Loss

**⚠️ CRITICAL - Vaultwarden**
- All passwords and vaults will be LOST unless exported first
- **MUST** export all vaults before migration
- After migration, import the exported data

**Speedtest Tracker**
- Historical speed test results will be lost
- Fresh start is acceptable for this service

**Uptime-Kuma**
- Monitoring history will be lost
- Will need to re-add monitors after migration

**Immich**
- Photos in `/mnt/nas/immich_upload` are safe
- Database schema will be recreated
- May lose some AI search metadata

### Pre-Migration Checklist

- [ ] Export Vaultwarden vaults (CRITICAL!)
- [ ] Note Uptime-Kuma monitors to re-add
- [ ] Verify PostgreSQL service is healthy
- [ ] Ensure Vault is accessible and authenticated
- [ ] Confirm NAS storage has adequate space

## Benefits

### Resource Savings

- **Removed 1 embedded PostgreSQL container** (Immich sidecar)
- **Consolidated 4 SQLite databases** into central PostgreSQL
- **Freed ~500MB memory** from Immich sidecar removal

### Operational Improvements

- **Single backup location** for all service databases
- **Centralized monitoring** of database performance
- **Easier recovery** from single PostgreSQL backup
- **Better resource utilization** with shared connection pooling
- **Consistent security** with Vault integration across all services

### Database Summary

After migration, the central PostgreSQL instance will have:

| Database | Service | Purpose |
|----------|---------|---------|
| freshrss | FreshRSS | RSS feed reader |
| gitea | Gitea | Git repository hosting |
| nextcloud | Nextcloud | File sharing and collaboration |
| authelia | Authelia | SSO authentication |
| grafana | Grafana | Monitoring dashboards |
| **immich** | **Immich** | **Photo backup and management** ✨ |
| **speedtest** | **Speedtest** | **Network speed monitoring** ✨ |
| **uptimekuma** | **Uptime-Kuma** | **Uptime monitoring** ✨ |
| **vaultwarden** | **Vaultwarden** | **Password manager** ✨ |

**Total: 9 services** on centralized PostgreSQL (5 existing + 4 migrated)

## Rollback Plan

If issues occur during migration:

```bash
# Checkout previous versions
git checkout HEAD~1 jobs/services/immich.nomad.hcl
git checkout HEAD~1 jobs/services/speedtest.nomad.hcl
git checkout HEAD~1 jobs/services/uptime-kuma.nomad.hcl
git checkout HEAD~1 jobs/services/vaultwarden.nomad.hcl

# Redeploy old versions
nomad job run jobs/services/immich.nomad.hcl
nomad job run jobs/services/speedtest.nomad.hcl
nomad job run jobs/services/uptime-kuma.nomad.hcl
nomad job run jobs/services/vaultwarden.nomad.hcl
```

## Post-Migration

### Verification

1. Check all services are accessible via web UI
2. Verify database connections in service logs
3. Monitor PostgreSQL resource usage
4. Check database sizes

### Cleanup (after 1-2 weeks)

Once confirmed working:

1. Remove `immich_postgres` volume from Nomad client config
2. Delete old PostgreSQL data: `rm -rf /mnt/nas/immich_postgres`
3. Remove SQLite backup files
4. Update architecture documentation

## Next Steps

1. **Run migration**: `task db:migrate`
2. **Export Vaultwarden data first!** (before running migration)
3. **Monitor services** for 24-48 hours
4. **Configure backups** for centralized PostgreSQL
5. **Document lessons learned**

## References

- Full documentation: [docs/DATABASE_MIGRATION.md](docs/DATABASE_MIGRATION.md)
- PostgreSQL job: [jobs/services/postgresql.nomad.hcl](jobs/services/postgresql.nomad.hcl)
- Migration script: [scripts/migrate-databases.fish](scripts/migrate-databases.fish)

---

## Lessons Learned

### Uptime-Kuma Reversal (February 12, 2026)

**Decision:** Reverted Uptime-Kuma from MariaDB back to SQLite.

**Reason - Monitoring Anti-Pattern:**  
Using a shared database for monitoring services creates a circular dependency:
- Monitor tracks database health
- Database goes down
- Monitor can't access its own data to report the outage
- Monitoring system is unavailable exactly when you need it most

**Real Impact:**  
When MariaDB went down during testing, Uptime-Kuma also went down, defeating the purpose of having a monitoring system.

**Solution:**  
Monitoring infrastructure should be operationally independent from monitored systems:
- ✅ **Uptime-Kuma**: SQLite (self-contained)
- ✅ **Alertmanager**: In-memory + config files
- ✅ **Prometheus**: Time-series DB (file-based)
- ✅ **Loki**: File-based log storage

**General Principle:**  
Database consolidation has diminishing returns and increases system fragility. Monitoring tools should have minimal external dependencies to remain operational during outages.

**Services to Keep Self-Contained:**
- Uptime monitoring (Uptime-Kuma)
- Alerting (Alertmanager)  
- Metrics collection (Prometheus)
- Log aggregation (Loki)
- Any service whose primary purpose is detecting failures

**Services Appropriate for Shared Databases:**
- Application data (Nextcloud, Gitea, Grafana)
- User authentication (Authelia)
- Content management (FreshRSS, Seafile)
- Non-critical utilities (Speedtest, Immich)

**Documentation:**  
See [TROUBLESHOOTING.md](TROUBLESHOOTING.md#uptime-kuma) for technical details on the migration issues encountered and solutions.

---

**Created**: February 6, 2026  
**Updated**: February 12, 2026 (Uptime-Kuma reversal)  
**Status**: Partially implemented - 3 services on PostgreSQL, 1 reverted  
**Impact**: Medium - requires service redeployment, potential data loss for some services
