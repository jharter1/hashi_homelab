# Database Topology & Consolidation Status

**Last Updated:** 2026-02-11  
**Phase:** Phase 2 (Database Consolidation)

## Overview

Database consolidation is **mostly complete** with shared PostgreSQL and MariaDB instances serving multiple applications. Some services are configured but databases not yet created.

## Shared Database Instances

### PostgreSQL (Job: `postgresql`)
- **Location:** Nomad allocation 29397ebe (postgres task group)
- **Version:** Latest (Docker image)
- **Storage:** `/mnt/nas/postgres_data` (NFS host volume)
- **Backup:** Automated daily backups via `postgres-backup` task (7-day retention)
- **Access:** Via Consul service discovery (`postgresql.home:5432`)
- **Admin Credentials:** Vault `secret/data/postgres/admin`

### MariaDB (Job: `mariadb`)
- **Location:** Nomad allocation (running on client nodes)
- **Version:** Latest (Docker image)
- **Storage:** `/mnt/nas/mariadb_data` (NFS host volume)
- **Access:** Direct IP 10.0.0.60:3306 (hardcoded in Seafile)
- **Admin Credentials:** Vault `secret/data/mariadb/admin`

## PostgreSQL Database Mappings

| Service | Database Name | User | Vault Secret Path | Status |
|---------|---------------|------|-------------------|--------|
| Authelia | `authelia` | `authelia` | `secret/data/postgres/authelia` | ✅ Active |
| Gitea | `gitea` | `gitea` | `secret/data/postgres/gitea` | ✅ Active |
| Grafana | `grafana` | `grafana` | `secret/data/postgres/grafana` | ✅ Active |
| Nextcloud | `nextcloud` | `nextcloud` | `secret/data/postgres/nextcloud` | ✅ Active |
| Speedtest | `speedtest` | `speedtest` | `secret/data/postgres/speedtest` | ✅ Active |
| FreshRSS | `freshrss` | `freshrss` | `secret/data/postgres/freshrss` | ❌ Job not running |
| Vaultwarden | `vaultwarden` | `vaultwarden` | `secret/data/postgres/vaultwarden` | ❌ Job not running |

**Active Databases:** 5 (authelia, gitea, grafana, nextcloud, speedtest)  
**Not Running:** 2 (freshrss, vaultwarden - jobs stopped/never deployed)

## MariaDB Database Mappings

| Service | Database Name | User | Vault Secret Path | Status |
|---------|---------------|------|-------------------|--------|
| Seafile | `ccnet_db`, `seafile_db`, `seahub_db` | `seafile` | `secret/data/mariadb/seafile` | ✅ Active |

**Note:** Seafile creates 3 databases during initialization.

## SQLite-Based Services (No Shared DB)

| Service | Storage Location | Reason for SQLite |
|---------|------------------|-------------------|
| Calibre | `/mnt/nas/calibre_data` | Embedded library database |
| Homepage | `/mnt/nas/homepage_data` | Lightweight config-only service |
| Uptime-Kuma | `/mnt/nas/uptime_kuma_data` | Self-contained monitoring (avoids dependency on monitored services) |

## Not Using Databases

| Service | Storage Type |
|---------|--------------|
| Alertmanager | In-memory + NFS config |
| Audiobookshelf | File-based library |
| Loki | Time-series file storage |
| MinIO | Object storage (S3-compatible) |
| Prometheus | Time-series file storage |
| Redis | In-memory key-value store |
| Traefik | Configuration-only |

## Architecture Patterns

### PostgreSQL Connection Pattern
```hcl
template {
  data = <<EOH
DATABASE_URL=postgresql://{{ .user }}:{{ with secret "secret/data/postgres/{{ .service }}" }}{{ .Data.data.password }}{{ end }}@{{ range service "postgresql" }}{{ .Address }}{{ end }}:5432/{{ .dbname }}
EOH
  destination = "secrets/db.env"
  env         = true
}
```

**Benefits:**
- Consul service discovery (no hardcoded IPs)
- Vault secret injection at task startup
- Dynamic password rotation support
- Automatic failover if PostgreSQL moves

### MariaDB Connection Pattern (Seafile)
```hcl
env {
  DB_HOST = "10.0.0.60"
  DB_PORT = "3306"
}

template {
  data = <<EOH
DB_ROOT_PASSWD={{ with secret "secret/data/mariadb/admin" }}{{ .Data.data.password }}{{ end }}
EOH
  destination = "secrets/db.env"
  env         = true
}
```

**Limitations:**
- Hardcoded IP (no service discovery)
- Should migrate to Consul service discovery pattern

## Consolidation Status

### ✅ Completed
1. Shared PostgreSQL instance deployed
2. Shared MariaDB instance deployed
3. 5 services actively using PostgreSQL (Authelia, Gitea, Grafana, Nextcloud, Speedtest)
4. 2 services using MariaDB (Seafile, Uptime-kuma)
5. Automated PostgreSQL backups (daily, 7-day retention)
6. All database credentials in Vault
7. Migrated uptime-kuma from SQLite to MariaDB (data wiped)

### ⚠️ Pending
1. **Decision needed on FreshRSS and Vaultwarden:**
   - Jobs exist but not running
   - If deploying: Create PostgreSQL databases first
   - If not needed: Remove job files to reduce clutter

3. **Improve MariaDB integration:**
   - Add Consul service discovery for MariaDB
   - Update Seafile job to use service discovery instead of hardcoded IP

4. **Add MariaDB backups:**
   - Similar to PostgreSQL backup task
   - Daily mariabackup or mysqldump
   - 7-day retention

### ❌ Not Applicable
- **Individual database containers:** None found (consolidation already complete)
- **Database migration needed:** No, all services already reference shared instances

## Database Creation Process

### Manual Database Creation (PostgreSQL)
```bash
# Get allocation ID
ALLOC_ID=$(curl -s http://10.0.0.50:4646/v1/job/postgresql/allocations | \
  python3 -c "import sys, json; print([a['ID'] for a in json.load(sys.stdin) if a['ClientStatus'] == 'running'][0])")

# Create database and user
nomad alloc exec -task postgres $ALLOC_ID sh -c '
PGPASSWORD=$POSTGRES_PASSWORD psql -U postgres <<SQL
CREATE DATABASE freshrss;
CREATE USER freshrss WITH PASSWORD '\''<from-vault>'\'';
GRANT ALL PRIVILEGES ON DATABASE freshrss TO freshrss;
\c freshrss
GRANT ALL ON SCHEMA public TO freshrss;
SQL
'
```

### Automated Database Creation (Recommended)
**Option 1:** Add init SQL scripts to PostgreSQL job's `/docker-entrypoint-initdb.d/`  
**Option 2:** Create Nomad batch job that runs database creation scripts  
**Option 3:** Add database creation to application job's prestart lifecycle hook

## Backup Strategy

### PostgreSQL Backups ✅
- **Method:** `pg_dumpall` (full cluster dump)
- **Schedule:** Daily at midnight (cron: `0 0 * * *`)
- **Location:** `/mnt/nas/postgres_data/backups/`
- **Retention:** 7 days
- **Task:** `postgres-backup` (sidecar in postgresql job)

### MariaDB Backups ⚠️
- **Status:** Not implemented yet
- **Recommended:** Add backup task to mariadb job
- **Method:** `mariabackup` or `mysqldump`
- **Schedule:** Daily at midnight
- **Location:** `/mnt/nas/mariadb_data/backups/`
- **Retention:** 7 days

## Performance Metrics

### Current Resource Usage
- **PostgreSQL Memory:** ~256 MB (check current allocation)
- **PostgreSQL CPU:** < 5% (idle state)
- **MariaDB Memory:** ~256 MB (check current allocation)
- **Databases per Instance:** PostgreSQL (5 active), MariaDB (1 active)
- **Total Database Count:** 6 logical databases across 2 instances

### Capacity Planning
- **Current:** 2 shared database instances serving 6 services
- **Target:** Same, plus 3 additional services when databases created
- **Future:** May need PostgreSQL replicas for HA (not currently implemented)

## Next Actions

1. **Immediate (Phase 2):**
   - [ ] Create missing PostgreSQL databases (freshrss, vaultwarden, uptimekuma)
   - [ ] Verify those services are running and can connect
   - [ ] Add MariaDB backup task (mirror PostgreSQL pattern)
   - [ ] Update Seafile to use Consul service discovery for MariaDB

2. **Short-term:**
   - [ ] Document database initialization process
   - [ ] Add automated database creation for new services
   - [ ] Monitor backup success/failure

3. **Long-term:**
   - [ ] PostgreSQL HA setup (multi-node cluster)
   - [ ] Database performance monitoring (pg_stat_statements)
   - [ ] Backup restoration testing
   - [ ] Database size monitoring and alerting
