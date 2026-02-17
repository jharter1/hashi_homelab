# Database Migration to Central PostgreSQL

This document describes the migration of services from SQLite/embedded databases to the centralized PostgreSQL instance.

## Overview

**Date**: February 6, 2026  
**Goal**: Consolidate all service databases into a single, centralized PostgreSQL instance for better management, backups, and performance.

## Services Migrated

| Service | Before | After | Notes |
|---------|--------|-------|-------|
| Immich | Embedded PostgreSQL (pgvecto-rs) | Central PostgreSQL | Requires pgvecto-rs extension |
| Speedtest Tracker | SQLite | Central PostgreSQL | Laravel app supports PostgreSQL natively |
| Uptime-Kuma | SQLite | Central PostgreSQL | Uses connection string format |
| Vaultwarden | SQLite | Central PostgreSQL | Bitwarden compatible password manager |

**Already using central PostgreSQL:**
- FreshRSS
- Gitea
- Nextcloud
- Authelia
- Grafana

## Prerequisites

1. **Central PostgreSQL running** at `postgresql.service.consul:5432`
2. **Vault cluster accessible** at `http://10.0.0.30:8200`
3. **Nomad cluster healthy** with workload identity enabled

## Migration Steps

### 1. Create Vault Secrets

Run the secret setup script to generate secure passwords:

```bash
fish scripts/setup-db-migration-secrets.fish
```

This creates Vault secrets at:
- `secret/postgres/immich`
- `secret/postgres/speedtest`
- `secret/postgres/uptimekuma`
- `secret/postgres/vaultwarden`

### 2. Backup Existing Data (IMPORTANT!)

Before migration, backup existing SQLite databases:

```bash
# Backup Speedtest data
nomad alloc exec <speedtest-alloc-id> cp /config/database.sqlite /config/database.sqlite.backup

# Backup Uptime-Kuma data
nomad alloc exec <uptime-kuma-alloc-id> cp /app/data/kuma.db /app/data/kuma.db.backup

# Backup Vaultwarden data
nomad alloc exec <vaultwarden-alloc-id> cp /data/db.sqlite3 /data/db.sqlite3.backup

# For Immich, the embedded PostgreSQL volume is preserved at /mnt/nas/immich_postgres
# This can be used for recovery if needed
```

### 3. Deploy Updated PostgreSQL

The PostgreSQL job now includes initialization scripts for the new databases:

```bash
# Stop current PostgreSQL
nomad job stop postgresql

# Wait for graceful shutdown
sleep 10

# Redeploy with new database initialization
nomad job run jobs/services/postgresql.nomad.hcl

# Monitor logs to confirm database creation
nomad alloc logs -f <postgres-alloc-id>
```

Expected log output:
```
PostgreSQL is ready. Creating databases and users...
Database initialization completed successfully!
```

### 4. Deploy Migrated Services

Deploy each service one at a time, monitoring for issues:

```bash
# Immich (most complex due to pgvecto-rs requirement)
nomad job run jobs/services/immich.nomad.hcl
nomad alloc logs -f <immich-alloc-id>

# Speedtest Tracker
nomad job run jobs/services/speedtest.nomad.hcl
nomad alloc logs -f <speedtest-alloc-id>

# Uptime-Kuma
nomad job run jobs/services/uptime-kuma.nomad.hcl
nomad alloc logs -f <uptime-kuma-alloc-id>

# Vaultwarden
nomad job run jobs/services/vaultwarden.nomad.hcl
nomad alloc logs -f <vaultwarden-alloc-id>
```

### 5. Verify Services

Check each service is operational:

```bash
# Check service health in Consul
consul catalog services

# Access web UIs
# Immich: https://immich.lab.hartr.net
# Speedtest: https://speedtest.lab.hartr.net
# Uptime-Kuma: https://uptime-kuma.lab.hartr.net
# Vaultwarden: https://vaultwarden.lab.hartr.net

# Verify database connections
nomad alloc exec <alloc-id> env | grep DB_
```

## Important Notes

### Immich Special Requirements

Immich requires the **pgvecto-rs** extension for AI-powered photo search. The central PostgreSQL instance needs to support this extension.

**⚠️ Current Limitation**: The standard PostgreSQL 16 Alpine image does not include pgvecto-rs. You have two options:

1. **Use separate Immich database** (recommended initially):
   - Keep the embedded `tensorchord/pgvecto-rs:pg14-v0.2.0` container
   - This migration already removed it, so we need to decide on approach

2. **Upgrade central PostgreSQL to support pgvecto-rs**:
   - Switch to `tensorchord/pgvecto-rs:pg16-v0.2.0` image
   - This provides vector support for all databases
   - Requires PostgreSQL redeployment

**Decision needed**: For now, Immich will connect to central PostgreSQL but may lose vector search features until we upgrade the main PostgreSQL image.

### Data Loss Scenarios

**Fresh Start Services** (data will be empty after migration):
- **Speedtest Tracker**: Historical speed test results will be lost
- **Uptime-Kuma**: Monitoring history will be lost
- **Vaultwarden**: All passwords/vaults will be lost (export before migration!)

**Data Preserved**:
- **Immich**: Photos stored in `/mnt/nas/immich_upload` are safe, but database schema needs migration

### Migration vs Fresh Start

For some services, a fresh start may be acceptable:
- **Speedtest**: Can rebuild history over time
- **Uptime-Kuma**: Can re-add monitors
- **Vaultwarden**: **CRITICAL - MUST EXPORT DATA FIRST**

For Vaultwarden specifically:
1. Export all vaults via web UI before migration
2. After migration, create new account
3. Import vaults from backup

## Rollback Procedure

If migration fails, rollback to previous configuration:

### 1. Restore Old Job Definitions

```bash
git checkout HEAD~1 jobs/services/immich.nomad.hcl
git checkout HEAD~1 jobs/services/speedtest.nomad.hcl
git checkout HEAD~1 jobs/services/uptime-kuma.nomad.hcl
git checkout HEAD~1 jobs/services/vaultwarden.nomad.hcl
```

### 2. Redeploy Old Versions

```bash
nomad job run jobs/services/immich.nomad.hcl
nomad job run jobs/services/speedtest.nomad.hcl
nomad job run jobs/services/uptime-kuma.nomad.hcl
nomad job run jobs/services/vaultwarden.nomad.hcl
```

### 3. Verify Services

Services should return to their previous state using SQLite/embedded databases.

## Post-Migration Cleanup

After confirming services work correctly for 1-2 weeks:

### 1. Remove Unused Volumes

```bash
# Remove old Immich PostgreSQL volume from Nomad client config
ssh ubuntu@<client-ip>
sudo nano /etc/nomad.d/nomad.hcl
# Remove immich_postgres host volume definition
sudo systemctl restart nomad
```

### 2. Clean Up Old Data

```bash
# Only after confirming data is safe in PostgreSQL!
ssh ubuntu@<client-ip>
sudo rm -rf /mnt/nas/immich_postgres
```

### 3. Update Documentation

Mark this migration as complete in:
- `README.md` - Update architecture section
- `ansible/TODO.md` - Check off database consolidation
- Taskfile.yml - Remove any old backup tasks

## Monitoring

### Database Size

Monitor PostgreSQL storage growth:

```sql
-- Connect to PostgreSQL
psql -h postgresql.service.consul -U postgres

-- Check database sizes
SELECT datname, pg_size_pretty(pg_database_size(datname)) 
FROM pg_database 
WHERE datname IN ('immich', 'speedtest', 'uptimekuma', 'vaultwarden')
ORDER BY pg_database_size(datname) DESC;

-- Check table sizes within a database
\c immich
SELECT schemaname, tablename, 
       pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
LIMIT 10;
```

### Connection Monitoring

Check active connections to new databases:

```sql
SELECT datname, count(*) 
FROM pg_stat_activity 
WHERE datname IN ('immich', 'speedtest', 'uptimekuma', 'vaultwarden')
GROUP BY datname;
```

## Backup Strategy

With centralized PostgreSQL, backups become simpler:

### Automated Backups

The PostgreSQL job includes a backup task that runs daily. Backups are stored at `/mnt/nas/postgres_backups/`.

### Manual Backup

```bash
# Backup all migrated databases
nomad alloc exec <postgres-alloc-id> pg_dumpall -U postgres > all_databases_backup.sql

# Backup specific database
nomad alloc exec <postgres-alloc-id> pg_dump -U postgres immich > immich_backup.sql
```

### Restore from Backup

```bash
# Restore single database
cat immich_backup.sql | nomad alloc exec -i <postgres-alloc-id> psql -U postgres immich

# Restore all databases (use with caution!)
cat all_databases_backup.sql | nomad alloc exec -i <postgres-alloc-id> psql -U postgres
```

## Troubleshooting

### Service Won't Start

Check logs for database connection errors:
```bash
nomad alloc logs <alloc-id>
```

Common issues:
- **Password mismatch**: Verify Vault secret matches PostgreSQL user
- **Database doesn't exist**: Check PostgreSQL init script ran successfully
- **Connection refused**: Ensure PostgreSQL service is registered in Consul

### Performance Issues

If services are slower after migration:

1. Check PostgreSQL resources (may need more CPU/memory)
2. Review connection pooling settings
3. Add indexes if queries are slow
4. Consider read replicas for high-traffic services

### Data Migration Errors

If you need to migrate existing SQLite data to PostgreSQL:

```bash
# Example for Speedtest Tracker (Laravel migration)
nomad alloc exec <speedtest-alloc-id> php artisan migrate:fresh
```

Each service has different migration procedures - consult their documentation.

## Security Considerations

### Vault Secrets

All database passwords are now stored in Vault and injected via templates. Never commit passwords to git or expose in job files.

### Network Security

Services connect to PostgreSQL over the internal network (10.0.0.0/24). For production:
- Enable SSL/TLS for PostgreSQL connections
- Use certificate authentication instead of passwords
- Implement connection limits per user

### Backup Encryption

For production environments:
- Encrypt backup files at rest
- Store backups off-site (different physical location)
- Test restore procedures regularly

## Future Enhancements

1. **PostgreSQL High Availability**
   - Add read replicas for scaling
   - Implement automatic failover with Patroni
   - Use pgpool for connection pooling

2. **Vector Extension for All**
   - Upgrade to `tensorchord/pgvecto-rs` base image
   - Enable AI features across all services

3. **Backup Automation**
   - Automated offsite backups to S3/MinIO
   - Point-in-time recovery capability
   - Backup monitoring and alerting

4. **Performance Optimization**
   - Query performance monitoring with pg_stat_statements
   - Automated VACUUM and ANALYZE scheduling
   - Index optimization for service-specific queries

---

**Migration Completed By**: AI Assistant  
**Date**: February 6, 2026  
**Status**: Ready for deployment - awaiting Vault secret creation
