# PostgreSQL - Database Management Guide

**Last Updated**: February 15, 2026

> ⚠️ **IMPORTANT ARCHITECTURAL PRINCIPLE**: Shared databases are an anti-pattern in containerized environments. See [Best Practices](#best-practices-the-right-way) below.

## Overview

This guide documents database management in the homelab, including the **current shared PostgreSQL setup** (legacy) and the **recommended per-service database pattern** (modern).

---

## ⚠️ Shared Database Anti-Pattern

### Why Shared Databases Are Wrong

The current homelab uses a **shared PostgreSQL instance** with multiple logical databases (one per service). This is an **anti-pattern** that should be avoided:

**Problems with Shared Databases:**

1. **Single Point of Failure** - If PostgreSQL crashes, ALL services go down
2. **Resource Contention** - Services compete for connections, memory, CPU
3. **No Service Isolation** - One service's bad query affects all others
4. **Complicated Scaling** - Can't scale individual service databases independently
5. **Blast Radius** - Database corruption/issues affect multiple services
6. **Upgrade Complexity** - PostgreSQL version upgrade impacts all services simultaneously
7. **Backup/Restore Complexity** - Can't restore one service without affecting others
8. **Security** - Lateral movement risk if one service is compromised

**Why It Happened:**
- Initial homelab setup prioritized resource efficiency over resilience
- Perceived "savings" in memory/storage
- Lack of understanding of containerized service boundaries
- Manual database creation overhead (now automated away)

### The Consolidation Mistake

The homelab went through a "database consolidation" phase (see archived migration docs):
- Started with services having their own SQLite/MariaDB instances
- Migrated many to shared PostgreSQL (Authelia, Gitea, Grafana, etc.)
- Attempted MariaDB for some services (Uptime-kuma)
- Eventually **reverted some decisions** (Uptime-kuma back to SQLite)

**Key Lesson:** Database consolidation reduces system resilience. Don't repeat this mistake.

---

## ✅ Best Practices (The Right Way)

### One Database Container Per Service

**Modern containerized architecture:**

```
Service A → PostgreSQL Container A (dedicated)
Service B → PostgreSQL Container B (dedicated)  
Service C → PostgreSQL Container C (dedicated)
Service D → SQLite (embedded, no network DB needed)
```

**Benefits:**

1. **Failure Isolation** - Service A's database crash doesn't affect Service B
2. **Independent Scaling** - Scale database resources per service demand
3. **Clear Ownership** - Each service owns and manages its data
4. **Simple Backups** - Backup/restore one service without affecting others
5. **Easy Versioning** - Service A uses PostgreSQL 16, Service B uses PostgreSQL 14
6. **Security Boundaries** - Network-level isolation between service databases
7. **Clean Removal** - Delete a service and its database cleanly

### Example: Correct Pattern

```hcl
job "myservice" {
  group "app" {
    # Service application
    task "server" {
      driver = "docker"
      config {
        image = "myapp:latest"
      }
      env {
        DATABASE_URL = "postgresql://myapp:password@127.0.0.1:5432/myapp"
      }
    }
    
    # Dedicated database for this service
    task "postgres" {
      driver = "docker"
      config {
        image = "postgres:16-alpine"
        network_mode = "host"
      }
      
      volume_mount {
        volume      = "myservice_db"
        destination = "/var/lib/postgresql/data"
      }
      
      env {
        POSTGRES_DB       = "myapp"
        POSTGRES_USER     = "myapp"
        POSTGRES_PASSWORD = "password"
      }
    }
    
    # Dedicated storage for this database
    volume "myservice_db" {
      type      = "host"
      source    = "myservice_db"
      read_only = false
    }
  }
}
```

**Key Principles:**

- ✅ Database runs in **same job group** as the application
- ✅ Database uses **dedicated host volume** for persistence
- ✅ Database lifecycle **tied to service lifecycle**
- ✅ **No shared connections** to other services
- ✅ Simple to **deploy/remove** as a unit

### When NOT to Use a Database

Many services don't need a networked database:

**Use SQLite or embedded storage for:**
- Configuration-only services (Homepage, Traefik)
- Personal libraries (Calibre, Audiobookshelf)
- Monitoring tools (Uptime-kuma - monitoring shouldn't depend on databases)
- Time-series data (Prometheus, Loki - optimized file formats)
- Simple key-value needs (Redis - in-memory)

**Rule of Thumb:** If a service can use SQLite successfully, there's no reason to introduce a networked database.

---

## Current Setup (Legacy - Do Not Expand)

### Shared PostgreSQL Instance

The homelab currently operates a **shared PostgreSQL instance** serving multiple services. This is **legacy architecture** being maintained for existing services, but **should not be expanded** to new services.

**Current Services Using Shared PostgreSQL:**

| Service       | Database      | Vault Secret Path             | Note |
|---------------|---------------|-------------------------------|------|
| Authelia      | `authelia`    | `secret/postgres/authelia`    | Should migrate |
| FreshRSS      | `freshrss`    | `secret/postgres/freshrss`    | Should migrate |
| Gitea         | `gitea`       | `secret/postgres/gitea`       | Should migrate |
| Grafana       | `grafana`     | `secret/postgres/grafana`     | Should migrate |
| Speedtest     | `speedtest`   | `secret/postgres/speedtest`   | Should migrate |
| Vaultwarden   | `vaultwarden` | `secret/postgres/vaultwarden` | Should migrate |

**Total:** 6 services sharing 1 PostgreSQL instance (6 logical databases)

**PostgreSQL Instance Details:**
- **Location:** Nomad job `postgresql`
- **Version:** postgres:16-alpine
- **Storage:** `/mnt/nas/postgres_data` (NFS host volume)
- **Access:** `postgresql.service.consul:5432` (Consul service discovery)
- **Admin Password:** Vault `secret/postgres/admin`

### Auto-Init System (Current Shared Setup)

The shared PostgreSQL instance includes an automated initialization system that creates databases/users on deployment.

**How It Works:**

```hcl
task "init-databases" {
  lifecycle {
    hook    = "poststart"  # Runs after PostgreSQL starts
    sidecar = false        # Exits after completion
  }
  
  template {
    data = <<EOH
#!/bin/sh
# Wait for PostgreSQL
until pg_isready; do sleep 1; done

# Idempotent database creation
psql -U postgres <<SQL
\c postgres
SELECT 'CREATE DATABASE mydb' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'mydb')\gexec
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'myuser') THEN
    CREATE USER myuser WITH ENCRYPTED PASSWORD '{{ with secret "secret/data/postgres/mydb" }}{{ .Data.data.password }}{{ end }}';
  END IF;
END $$;
GRANT ALL PRIVILEGES ON DATABASE mydb TO myuser;
SQL
EOH
  }
}
```

**Adding a Database (If You Must):**

1. Create Vault secret:
   ```bash
   vault kv put secret/postgres/myservice password="$(openssl rand -base64 32)"
   ```

2. Add SQL block to `postgresql.nomad.hcl` init template

3. Redeploy PostgreSQL (idempotent):
   ```bash
   nomad job run jobs/services/postgresql.nomad.hcl
   ```

**Verification:**

```bash
# Check init logs
ALLOC_ID=$(nomad job status postgresql | grep running | head -1 | awk '{print $1}')
nomad alloc logs $ALLOC_ID init-databases

# List databases
nomad alloc exec -task postgres $ALLOC_ID psql -U postgres -c "\l"
```

### Connection Pattern (Current Services)

Services connect via Consul service discovery and Vault secrets:

```hcl
template {
  destination = "secrets/db.env"
  env         = true
  data        = <<EOH
DB_HOST={{ range service "postgresql" }}{{ .Address }}{{ end }}
DB_PORT=5432
DB_DATABASE=myservice
DB_USERNAME=myservice
DB_PASSWORD={{ with secret "secret/data/postgres/myservice" }}{{ .Data.data.password }}{{ end }}
EOH
}
```

**Benefits:**
- No hardcoded IPs (Consul service discovery)
- Secure password injection (Vault)
- Automatic failover if PostgreSQL moves nodes

**Drawbacks:**
- See [Shared Database Anti-Pattern](#shared-database-anti-pattern) above

---

## Migration Path: Shared → Dedicated

### Migrating Services to Dedicated Databases

For each service currently using the shared PostgreSQL:

#### 1. Backup Current Data

```bash
# Export service database
ALLOC_ID=$(nomad job status postgresql | grep running | head -1 | awk '{print $1}')
nomad alloc exec -task postgres $ALLOC_ID \
  pg_dump -U postgres myservice > myservice_backup.sql
```

#### 2. Create New Job with Dedicated Database

```hcl
job "myservice" {
  group "app" {
    volume "db_data" {
      type      = "host"
      source    = "myservice_db"
      read_only = false
    }
    
    # Application task
    task "server" {
      driver = "docker"
      config {
        image = "myservice:latest"
      }
      env {
        DB_HOST     = "127.0.0.1"  # Local to task group
        DB_PORT     = "5432"
        DB_DATABASE = "myservice"
        DB_USERNAME = "myservice"
        DB_PASSWORD = "mypassword"
      }
    }
    
    # Dedicated PostgreSQL task
    task "postgres" {
      driver = "docker"
      config {
        image        = "postgres:16-alpine"
        network_mode = "host"
        port_map {
          db = 5432
        }
      }
      
      volume_mount {
        volume      = "db_data"
        destination = "/var/lib/postgresql/data"
      }
      
      env {
        POSTGRES_DB       = "myservice"
        POSTGRES_USER     = "myservice"
        POSTGRES_PASSWORD = "mypassword"
      }
    }
  }
}
```

#### 3. Import Data to New Database

```bash
# Wait for new database to be ready
ALLOC_ID=$(nomad job status myservice | grep running | head -1 | awk '{print $1}')

# Import backup
cat myservice_backup.sql | nomad alloc exec -i -task postgres $ALLOC_ID \
  psql -U myservice -d myservice
```

#### 4. Update Service Configuration

- Remove Consul service discovery for database
- Change `DB_HOST` from Consul template to `127.0.0.1`
- Use local credentials (or Vault if preferred)

#### 5. Test and Verify

```bash
# Test application connectivity
nomad alloc logs -f $ALLOC_ID server

# Verify data integrity
nomad alloc exec -task postgres $ALLOC_ID \
  psql -U myservice -d myservice -c "SELECT count(*) FROM <important_table>;"
```

#### 6. Remove from Shared PostgreSQL

Once migration is verified:

```bash
# Remove database from shared instance (optional)
SHARED_ALLOC=$(nomad job status postgresql | grep running | head -1 | awk '{print $1}')
nomad alloc exec -task postgres $SHARED_ALLOC \
  psql -U postgres -c "DROP DATABASE myservice; DROP USER myservice;"

# Remove from init-databases task in postgresql.nomad.hcl
# Redeploy: nomad job run jobs/services/postgresql.nomad.hcl
```

### Migration Priority

**High Priority (migrate first):**
1. **Speedtest Tracker** - Standalone service, easy migration
2. **FreshRSS** - RSS reader, self-contained
3. **Vaultwarden** - Password manager, should be isolated

**Medium Priority:**
4. **Grafana** - Monitoring, but benefits from isolation
5. **Authelia** - SSO, but critical service

**Low Priority (keep for now):**
6. **Gitea** - Source control, high complexity

### Expected Results

After migrating all services:
- **Shared PostgreSQL:** Decommissioned entirely
- **Each service:** Has dedicated database container
- **Resilience:** Improved significantly
- **Complexity:** Reduced (no shared state management)

---

## Troubleshooting

### Shared PostgreSQL Issues

#### Database Not Created Despite Init Script

**Symptom:** Service shows "password authentication failed" but database doesn't exist.

**Diagnosis:**
```bash
# Check if init task ran
ALLOC_ID=$(nomad job status postgresql | grep running | head -1 | awk '{print $1}')
nomad alloc status $ALLOC_ID | grep init-databases
# Should show "complete"

# Check init logs
nomad alloc logs $ALLOC_ID init-databases
# Should show "Database initialization completed successfully!"

# Verify database exists
nomad alloc exec -task postgres $ALLOC_ID psql -U postgres -c "\l" | grep myservice
```

**Solutions:**

1. **Redeploy PostgreSQL** (idempotent):
   ```bash
   nomad job run jobs/services/postgresql.nomad.hcl
   ```

2. **Manual creation** (if needed):
   ```bash
   PASSWORD=$(vault kv get -field=password secret/postgres/myservice)
   ALLOC_ID=$(nomad job status postgresql | grep running | head -1 | awk '{print $1}')
   
   nomad alloc exec -task postgres $ALLOC_ID psql -U postgres -c \
     "CREATE DATABASE myservice;"
   nomad alloc exec -task postgres $ALLOC_ID psql -U postgres -c \
     "CREATE USER myservice WITH ENCRYPTED PASSWORD '$PASSWORD';"
   nomad alloc exec -task postgres $ALLOC_ID psql -U postgres -c \
     "GRANT ALL PRIVILEGES ON DATABASE myservice TO myservice;"
   ```

#### Connection Refused

**Symptom:** Service can't connect to PostgreSQL.

**Check:**
```bash
# Verify PostgreSQL is running
consul catalog service postgresql

# Test connectivity from service allocation
SERVICE_ALLOC=$(nomad job status myservice | grep running | head -1 | awk '{print $1}')
nomad alloc exec $SERVICE_ALLOC \
  wget -O- http://postgresql.service.consul:5432
# Should connect (may show PostgreSQL protocol response)
```

#### Vault Template Rendering Failures

**Symptom:** Init task shows "vault.read: permission denied"

**Solution:**
```bash
# Verify Vault policy allows access
vault policy read nomad-workloads | grep postgres
# Should show: path "secret/data/postgres/*"

# Ensure PostgreSQL job has vault block
grep -A 2 "task \"postgres\"" jobs/services/postgresql.nomad.hcl | grep vault
# Should show: vault {}
```

### Dedicated Database Issues

#### Database Won't Start

**Check logs:**
```bash
ALLOC_ID=$(nomad job status myservice | grep running | head -1 | awk '{print $1}')
nomad alloc logs $ALLOC_ID postgres
```

**Common causes:**
- Incorrect permissions on host volume
- Port conflict (another PostgreSQL on same node)
- Corrupted data directory

**Solutions:**
```bash
# Check host volume permissions
ssh ubuntu@<node-ip> "ls -la /mnt/nas/myservice_db"
# Should be owned by docker user or have 777 permissions

# Check for port conflicts
ssh ubuntu@<node-ip> "sudo netstat -tlnp | grep 5432"

# Reset data directory (destructive - backup first!)
ssh ubuntu@<node-ip> "sudo rm -rf /mnt/nas/myservice_db/*"
nomad job run jobs/services/myservice.nomad.hcl
```

#### Service Can't Connect to Local Database

**Check network mode:**
```hcl
# Both tasks must use same network mode
task "server" {
  config {
    network_mode = "host"  # or "bridge"
  }
}

task "postgres" {
  config {
    network_mode = "host"  # Match server task
  }
}
```

**Verify connectivity:**
```bash
# From service task
ALLOC_ID=$(nomad job status myservice | grep running | head -1 | awk '{print $1}')
nomad alloc exec -task server $ALLOC_ID \
  wget -O- http://127.0.0.1:5432
```

---

## Backup & Recovery

### Shared PostgreSQL Backups

Current automated backup task:
```hcl
task "postgres-backup" {
  lifecycle {
    hook    = "poststart"
    sidecar = true
  }
  
  # Runs daily at midnight
  config {
    command = "crond"
    args    = ["-f"]
  }
  
  # Cron job: 0 0 * * * pg_dumpall > /backups/$(date +%Y%m%d).sql
}
```

**Backup location:** `/mnt/nas/postgres_data/backups/`  
**Retention:** 7 days  
**Scope:** Full cluster (all databases)

**Manual backup:**
```bash
ALLOC_ID=$(nomad job status postgresql | grep running | head -1 | awk '{print $1}')
nomad alloc exec -task postgres $ALLOC_ID \
  pg_dumpall -U postgres > postgres_backup_$(date +%Y%m%d).sql
```

**Restore:**
```bash
cat postgres_backup_20260215.sql | nomad alloc exec -i -task postgres $ALLOC_ID \
  psql -U postgres
```

### Dedicated Database Backups

Each service should implement its own backup strategy:

```hcl
task "db-backup" {
  lifecycle {
    hook    = "poststart"
    sidecar = true
  }
  
  driver = "docker"
  config {
    image   = "postgres:16-alpine"
    command = "sh"
    args    = ["-c", "while true; do pg_dump -U myservice -d myservice > /backup/$(date +%Y%m%d).sql; sleep 86400; done"]
  }
  
  volume_mount {
    volume      = "backup_data"
    destination = "/backup"
  }
}
```

**Better approach:** Use external backup tools
- pgBackRest
- Barman
- Cloud backups (S3, B2)

---

## Best Practices Summary

### ✅ DO

1. **Deploy dedicated databases** for new services
2. **Use SQLite** when a networked database isn't needed
3. **Isolate service data** at the infrastructure level
4. **Back up each database independently**
5. **Version databases per service** (PostgreSQL 14, 16, etc. as needed)
6. **Test backups regularly** (restore to verify integrity)

### ❌ DON'T

1. **Don't share databases** across services (anti-pattern)
2. **Don't add new databases** to shared PostgreSQL
3. **Don't consolidate for "efficiency"** (reduces resilience)
4. **Don't skip backups** (even for dedicated databases)
5. **Don't use production data in tests** (create test databases)
6. **Don't hardcode IPs** (use Consul for shared setups, localhost for dedicated)

---

## Future Work

### Short Term
- [ ] Migrate Speedtest Tracker to dedicated database
- [ ] Migrate FreshRSS to dedicated database
- [ ] Migrate Vaultwarden to dedicated database

### Medium Term
- [ ] Migrate Grafana to dedicated database
- [ ] Migrate Authelia to dedicated database
- [ ] Document per-service backup strategies

### Long Term
- [ ] Decommission shared PostgreSQL entirely
- [ ] Migrate Gitea to dedicated database
- [ ] Migrate Nextcloud to dedicated database
- [ ] Update all documentation to reflect dedicated pattern

---

## References

- PostgreSQL Documentation: https://www.postgresql.org/docs/
- Nomad Volume Management: https://developer.hashicorp.com/nomad/docs/job-specification/volume
- 12-Factor App Backing Services: https://12factor.net/backing-services
- Consul Service Discovery: https://developer.hashicorp.com/consul/docs/discovery/services

### Related Documentation

- [Vault Integration](VAULT.md) - Secret management for database credentials
- [NEW_SERVICES_DEPLOYMENT.md](NEW_SERVICES_DEPLOYMENT.md) - Service deployment patterns
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - General troubleshooting guide

### Historical Context

For historical migration documentation, see `docs/archive/migrations/`:
- Database consolidation summary (completed 2026-02)
- PostgreSQL migration plans (historical)
- Lessons learned from consolidation attempts
