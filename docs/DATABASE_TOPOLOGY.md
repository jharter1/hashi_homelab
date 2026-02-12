# Database Topology & Consolidation Status

**Last Updated:** 2026-02-12  
**Phase:** ✅ Complete

## Overview

Database consolidation is **complete** with a shared PostgreSQL instance serving multiple applications. All active services using databases are connected via Vault credentials and Consul service discovery.

## Shared Database Instances

### PostgreSQL (Job: `postgresql`)
- **Location:** Nomad allocation (postgres task group)
- **Version:** Latest (Docker image)
- **Storage:** `/mnt/nas/postgres_data` (NFS host volume)
- **Backup:** Automated daily backups via `postgres-backup` task (7-day retention)
- **Access:** Via Consul service discovery (`postgresql.home:5432`)
- **Admin Credentials:** Vault `secret/data/postgres/admin`

## PostgreSQL Database Mappings

| Service | Database Name | User | Vault Secret Path | Status |
|---------|---------------|------|-------------------|--------|
| Authelia | `authelia` | `authelia` | `secret/data/postgres/authelia` | ✅ Active |
| Gitea | `gitea` | `gitea` | `secret/data/postgres/gitea` | ✅ Active |
| Grafana | `grafana` | `grafana` | `secret/data/postgres/grafana` | ✅ Active |
| Nextcloud | `nextcloud` | `nextcloud` | `secret/data/postgres/nextcloud` | ✅ Active |
| Speedtest | `speedtest` | `speedtest` | `secret/data/postgres/speedtest` | ✅ Active |
| FreshRSS | `freshrss` | `freshrss` | `secret/data/postgres/freshrss` | ✅ Active |
| Vaultwarden | `vaultwarden` | `vaultwarden` | `secret/data/postgres/vaultwarden` | ✅ Active |

**Active Databases:** 7  
**Total Services:** 7 (authelia, gitea, grafana, nextcloud, speedtest, freshrss, vaultwarden)

## Abandoned Database Instances

### MariaDB
- **Status:** ❌ Abandoned
- **Reason:** Complexity not worth maintaining for single service (Uptime-kuma)
- **Decision:** Uptime-kuma reverted to SQLite standalone database
- **Learning:** Database consolidation has diminishing returns and increases system fragility

## SQLite-Based Services (No Shared DB)

| Service | Storage Location | Reason for SQLite |
|---------|------------------|-------------------|
| Calibre | `/mnt/nas/calibre_data` | Embedded library database |
| Homepage | `/mnt/nas/homepage_data` | Lightweight config-only service |
| Uptime-kuma | `/mnt/nas/uptime_kuma_data` | Self-contained monitoring, reverted from MariaDB |

## Not Using Databases

| Service | Storage Type | Notes |
|---------|--------------|-------|
| Alertmanager | In-memory + NFS config | |
| Audiobookshelf | File-based library | |
| Loki | Time-series file storage | |
| MinIO | Object storage (S3-compatible) | |
| Prometheus | Time-series file storage | |
| Redis | In-memory key-value store | |
| Syncthing | File synchronization | Replaces Seafile |
| Traefik | Configuration-only | |

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

### SQLite Pattern (Uptime-kuma)
```hcl
volume "uptime_kuma_data" {
  type      = "host"
  source    = "uptime_kuma_data"
  read_only = false
}

volume_mount {
  volume      = "uptime_kuma_data"
  destination = "/app/data"
}
```

**Benefits:**
- Self-contained, no external dependencies
- Simpler operational model
- Monitoring shouldn't depend on monitored services

## Consolidation Status

### ✅ Completed
1. ✅ Shared PostgreSQL instance deployed
2. ✅ 7 services actively using PostgreSQL (Authelia, Gitea, Grafana, Nextcloud, Speedtest, FreshRSS, Vaultwarden)
3. ✅ Automated PostgreSQL backups (daily, 7-day retention)
4. ✅ All database credentials in Vault
5. ✅ All PostgreSQL services using Consul service discovery (no hardcoded IPs)
6. ✅ FreshRSS deployed with PostgreSQL
7. ✅ Vaultwarden deployed with PostgreSQL (fixed schema permissions issue)
8. ❌ MariaDB experiment abandoned (reverted Uptime-kuma to SQLite)

### ✅ Database Anti-Pattern Note
Further database consolidation is considered an anti-pattern that reduces system resilience:
- Creates single points of failure
- Increases blast radius for database issues
- Complicates resource isolation
- Makes independent service scaling harder

**Decision:** Database migration phase is complete. Future services should evaluate database needs independently.

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
- **PostgreSQL Memory:** ~256 MB baseline
- **PostgreSQL CPU:** < 5% (idle state)
- **Databases per Instance:** PostgreSQL (7 active)
- **Total Database Count:** 7 logical databases in 1 shared instance

### Capacity Planning
- **Current:** 1 shared PostgreSQL instance serving 7 services
- **Headroom:** Can handle 10-15 more databases on current resources
- **Future HA:** PostgreSQL replicas not planned (accepted risk for homelab)

## Lessons Learned

### Technical Wins
1. ✅ **Consul Service Discovery:** Eliminates hardcoded IPs, enables dynamic routing
2. ✅ **Vault Integration:** Centralized credential management with rotation capability
3. ✅ **Template Variable Scoping:** Pattern for mixing Vault/Consul contexts: `{{ $var := .Data }}{{ range }}{{ $var }}{{ end }}`
4. ✅ **Automated Backups:** PostgreSQL backup task runs daily without manual intervention

### Service-Specific Challenges
1. **Vaultwarden:** Required 4 fixes (schema permissions, template scoping, network mode, ROCKET_PORT)
2. **PostgreSQL 15+:** Changed default schema permissions, need explicit `GRANT ALL ON SCHEMA public`
3. **Seafile:** Complex initialization requirements incompatible with shared database model (abandoned)

### Migration Decisions
- **Uptime-kuma:** SQLite → MariaDB → SQLite (reverted, monitoring shouldn't depend on databases)
- **Seafile:** Abandoned in favor of Syncthing (complexity not worth it)
- **MariaDB:** Abandoned entirely (not worth maintaining for edge cases)
- **Future:** No further database consolidation (anti-pattern for resilience)

## Optional Future Work

- [ ] PostgreSQL performance monitoring (pg_stat_statements)
- [ ] Backup restoration testing
- [ ] Database size alerting
- [ ] PostgreSQL query optimization for slow queries
