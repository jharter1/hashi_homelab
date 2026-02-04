# PostgreSQL Migration Plan - Homelab Services

## Current State

### ✅ What's Already Working
- **PostgreSQL 16.11** running on Nomad (10.0.0.61:5432)
- **Vault-Nomad Integration** fully operational with JWT/Workload Identity
- **Vault Secrets** configured for all database users at `secret/postgres/*`:
  - `secret/postgres/admin` - PostgreSQL superuser
  - `secret/postgres/grafana` - Grafana database user
  - `secret/postgres/gitea` - Gitea database user
  - `secret/postgres/nextcloud` - Nextcloud database user
  - `secret/postgres/authelia` - Authelia database user
  - `secret/postgres/freshrss` - FreshRSS database user

### 🗄️ Pre-Created Databases
PostgreSQL initialization script has already created:
- `grafana` database with `grafana` user
- `gitea` database with `gitea` user
- `nextcloud` database with `nextcloud` user
- `authelia` database with `authelia` user
- `freshrss` database with `freshrss` user

All users have GRANT ALL PRIVILEGES on their respective databases.

### 📋 Services to Migrate
1. **Nextcloud** - Currently SQLite (HIGH priority)
2. **Gitea** - Currently SQLite (HIGH priority)
3. **Grafana** - Currently SQLite (MEDIUM priority)
4. **Authelia** - Currently SQLite (MEDIUM priority)
5. **Vaultwarden** - Currently SQLite (MEDIUM priority - needs new DB)
6. **Uptime-Kuma** - Currently SQLite (LOW priority - needs new DB)

---

## Migration Strategy

### General Approach
For each service:
1. **Backup existing SQLite database** (if data exists)
2. **Add `vault {}` block** to Nomad job for secrets access
3. **Add Vault template** to inject database password
4. **Update environment variables** to use PostgreSQL
5. **Deploy updated job** and verify connectivity
6. **Migrate data** if service has existing data
7. **Verify functionality** and test
8. **Remove old SQLite files** (after confirmation)

### PostgreSQL Connection Details
- **Host**: `postgresql.service.consul` (via Consul DNS) or `10.0.0.61`
- **Port**: `5432`
- **SSL**: Disabled (internal homelab network)

---

## Migration Plans by Service

### 1. Nextcloud (HIGH Priority)

**Why Migrate**: Nextcloud explicitly recommends against SQLite for production. PostgreSQL provides much better performance with file operations and concurrent users.

**Current State**:
- Job: `jobs/services/nextcloud.nomad.hcl`
- Using: Auto-detected SQLite
- Volume: `/mnt/nas/nextcloud/data` and `/mnt/nas/nextcloud/config`

**Migration Steps**:
1. Add `vault {}` block to task
2. Add Vault template for database password:
   ```hcl
   vault {}
   
   template {
     destination = "secrets/db.env"
     env         = true
     data        = <<EOH
   POSTGRES_PASSWORD={{ with secret "secret/data/postgres/nextcloud" }}{{ .Data.data.password }}{{ end }}
   EOH
   }
   ```

3. Update environment variables:
   ```hcl
   env {
     POSTGRES_HOST = "postgresql.service.consul"
     POSTGRES_DB = "nextcloud"
     POSTGRES_USER = "nextcloud"
     # POSTGRES_PASSWORD comes from Vault template
     
     NEXTCLOUD_TRUSTED_DOMAINS = "nextcloud.home"
   }
   ```

4. **First-time setup**: Nextcloud will auto-detect PostgreSQL on first run
5. **Existing data**: Use Nextcloud's occ command to migrate:
   ```bash
   nomad alloc exec <alloc-id> -task nextcloud \
     php occ db:convert-type pgsql nextcloud \
     postgresql.service.consul nextcloud
   ```

**Verification**:
- Access http://nextcloud.home
- Check Admin → Overview for database type
- Upload/download files to test performance
- Check logs: `nomad alloc logs <alloc-id> nextcloud`

---

### 2. Gitea (HIGH Priority)

**Why Migrate**: Git operations benefit from proper database transactions, better concurrency, and reliable backups.

**Current State**:
- Job: `jobs/services/gitea.nomad.hcl`
- Using: SQLite at `/data/gitea/gitea.db`
- Volume: `/mnt/nas/gitea`

**Migration Steps**:
1. Add `vault {}` block to task
2. Add Vault template:
   ```hcl
   vault {}
   
   template {
     destination = "secrets/db.env"
     env         = true
     data        = <<EOH
   DB_PASSWORD={{ with secret "secret/data/postgres/gitea" }}{{ .Data.data.password }}{{ end }}
   EOH
   }
   ```

3. Update environment variables:
   ```hcl
   env {
     USER_UID = "1000"
     USER_GID = "1000"
     
     # Database configuration
     GITEA__database__DB_TYPE = "postgres"
     GITEA__database__HOST = "postgresql.service.consul:5432"
     GITEA__database__NAME = "gitea"
     GITEA__database__USER = "gitea"
     GITEA__database__PASSWD = "${DB_PASSWORD}"  # From Vault template
     GITEA__database__SSL_MODE = "disable"
     
     # Server configuration
     GITEA__server__DOMAIN = "gitea.home"
     GITEA__server__SSH_DOMAIN = "gitea.home"
     GITEA__server__SSH_PORT = "2222"
     GITEA__server__HTTP_PORT = "3000"
     GITEA__server__ROOT_URL = "http://gitea.home"
     GITEA__server__DISABLE_SSH = "false"
   }
   ```

4. **Data migration**: Gitea will auto-migrate on startup OR use gitea dump/restore:
   ```bash
   # Backup existing data
   nomad alloc exec <old-alloc> gitea dump -c /data/gitea/conf/app.ini
   
   # After deploying new version, restore if needed
   nomad alloc exec <new-alloc> gitea restore --from <dump-file>
   ```

**Verification**:
- Access http://gitea.home
- Check Admin → Configuration → Database
- Clone a repository
- Push changes
- Check logs: `nomad alloc logs <alloc-id> gitea`

---

### 3. Grafana (MEDIUM Priority)

**Why Migrate**: Better dashboard persistence, multi-user sessions, and query performance.

**Current State**:
- Job: `jobs/services/grafana.nomad.hcl`
- Using: Default SQLite (embedded)
- Volume: `/mnt/nas/grafana`

**Migration Steps**:
1. Add `vault {}` block to task
2. Add Vault template:
   ```hcl
   vault {}
   
   template {
     destination = "secrets/db.env"
     env         = true
     data        = <<EOH
   GF_DATABASE_PASSWORD={{ with secret "secret/data/postgres/grafana" }}{{ .Data.data.password }}{{ end }}
   EOH
   }
   ```

3. Update environment variables:
   ```hcl
   env {
     # Database configuration
     GF_DATABASE_TYPE = "postgres"
     GF_DATABASE_HOST = "postgresql.service.consul:5432"
     GF_DATABASE_NAME = "grafana"
     GF_DATABASE_USER = "grafana"
     # GF_DATABASE_PASSWORD from Vault template
     GF_DATABASE_SSL_MODE = "disable"
     
     # Security
     GF_SECURITY_ADMIN_PASSWORD = "admin"
     GF_SERVER_HTTP_PORT = "3000"
     
     # Server configuration
     GF_SERVER_ROOT_URL = "http://grafana.home"
     GF_SERVER_SERVE_FROM_SUB_PATH = "false"
     GF_SERVER_ENFORCE_DOMAIN = "false"
     GF_SERVER_PROTOCOL = "http"
     GF_SERVER_ENABLE_GZIP = "true"
     GF_AUTH_ANONYMOUS_ENABLED = "false"
   }
   ```

4. **Data migration**: Grafana will auto-migrate on first PostgreSQL connection
   - Dashboards, data sources, and users preserved
   - Or manually backup: Settings → Configuration → Export JSON

**Verification**:
- Access http://grafana.home
- Check Configuration → Data Sources
- Verify dashboards load
- Check Server Admin → Stats for database type
- Check logs: `nomad alloc logs <alloc-id> grafana`

---

### 4. Authelia (MEDIUM Priority)

**Why Migrate**: Better session management, user tracking, and multi-instance support.

**Current State**:
- Job: `jobs/services/authelia.nomad.hcl`
- Using: SQLite at `/data/db.sqlite3`
- Volume: `/mnt/nas/authelia`

**Migration Steps**:
1. Add `vault {}` block to task
2. Add Vault template:
   ```hcl
   vault {}
   
   template {
     destination = "secrets/db.env"
     env         = true
     data        = <<EOH
   AUTHELIA_STORAGE_POSTGRES_PASSWORD={{ with secret "secret/data/postgres/authelia" }}{{ .Data.data.password }}{{ end }}
   EOH
   }
   ```

3. Update configuration template (in existing template block):
   ```hcl
   template {
     destination = "local/configuration.yml"
     data        = <<EOH
   # ... existing config ...
   
   storage:
     postgres:
       host: postgresql.service.consul
       port: 5432
       database: authelia
       username: authelia
       password: ${AUTHELIA_STORAGE_POSTGRES_PASSWORD}
       sslmode: disable
   
   # ... rest of config ...
   EOH
   }
   ```

4. **Data migration**: Manual migration required:
   - Export users from SQLite
   - Import to PostgreSQL
   - Or fresh start (minimal user data in homelab)

**Verification**:
- Access http://authelia.home
- Test login/logout
- Check user sessions persist
- Check logs: `nomad alloc logs <alloc-id> authelia`

---

### 5. Vaultwarden (MEDIUM Priority)

**Why Migrate**: Password manager benefits from PostgreSQL's reliability and backup capabilities.

**Current State**:
- Job: `jobs/services/vaultwarden.nomad.hcl`
- Using: SQLite at `/data/db.sqlite3`
- Volume: `/mnt/nas/vaultwarden`

**Prerequisites**:
1. Create `vaultwarden` database and user in PostgreSQL:
   ```sql
   CREATE DATABASE vaultwarden;
   CREATE USER vaultwarden WITH ENCRYPTED PASSWORD '<generate-password>';
   GRANT ALL PRIVILEGES ON DATABASE vaultwarden TO vaultwarden;
   \c vaultwarden
   GRANT ALL ON SCHEMA public TO vaultwarden;
   ```

2. Store password in Vault:
   ```bash
   vault kv put secret/postgres/vaultwarden password="<generated-password>"
   ```

3. Update PostgreSQL init script to include vaultwarden (optional, for future rebuilds)

**Migration Steps**:
1. Add `vault {}` block to task
2. Add Vault template:
   ```hcl
   vault {}
   
   template {
     destination = "secrets/db.env"
     env         = true
     data        = <<EOH
   DB_PASSWORD={{ with secret "secret/data/postgres/vaultwarden" }}{{ .Data.data.password }}{{ end }}
   EOH
   }
   ```

3. Update environment variables:
   ```hcl
   env {
     # Database configuration
     DATABASE_URL = "postgresql://vaultwarden:${DB_PASSWORD}@postgresql.service.consul:5432/vaultwarden"
     
     # Existing config
     SIGNUPS_ALLOWED = "true"
     DOMAIN = "http://vaultwarden.home"
     WEBSOCKET_ENABLED = "true"
     LOG_LEVEL = "warn"
     DISABLE_YUBICO = "true"
   }
   ```

4. **Data migration**: Use vaultwarden's built-in migration OR export/import:
   - Backup via web UI: Admin → Backup
   - Deploy new version with PostgreSQL
   - Restore backup

**Verification**:
- Access http://vaultwarden.home
- Login with existing account
- Verify all passwords/items present
- Test sync across devices
- Check logs: `nomad alloc logs <alloc-id> vaultwarden`

---

### 6. Uptime-Kuma (LOW Priority)

**Why Migrate**: Better performance with many monitors, but SQLite works fine.

**Current State**:
- Job: `jobs/services/uptime-kuma.nomad.hcl`
- Using: SQLite (embedded)
- Volume: `/mnt/nas/uptime-kuma`

**Note**: Uptime-Kuma v2 has limited PostgreSQL support. May require specific version or configuration. Recommend leaving on SQLite unless needed.

**Migration Steps** (if desired):
1. Check Uptime-Kuma documentation for PostgreSQL support
2. Similar pattern to other services
3. May require manual data migration

---

## General Workflow for Each Migration

### Pre-Migration Checklist
- [ ] Verify PostgreSQL database exists
- [ ] Verify Vault secret exists for database user
- [ ] Backup current SQLite database
- [ ] Note current service version
- [ ] Document current configuration

### Migration Execution
1. **Stop old job** (if fresh install) or prepare for rolling update
2. **Update Nomad job file** with Vault integration and PostgreSQL config
3. **Deploy updated job**: `nomad job run jobs/services/<service>.nomad.hcl`
4. **Monitor deployment**: `nomad job status <service>`
5. **Check allocation**: `nomad alloc status <alloc-id>`
6. **Verify logs**: `nomad alloc logs <alloc-id>`

### Post-Migration Verification
- [ ] Service accessible via web UI
- [ ] Database connection working (check logs)
- [ ] Existing data present (if migrated)
- [ ] Functionality tests pass
- [ ] Performance acceptable
- [ ] Backups working (PostgreSQL backup task)

### Rollback Procedure
If migration fails:
1. Stop failed allocation: `nomad job stop <service>`
2. Revert Nomad job to use SQLite configuration
3. Redeploy: `nomad job run jobs/services/<service>.nomad.hcl`
4. Restore SQLite backup if data corrupted
5. Debug issue before retry

---

## Migration Order (Recommended)

### Phase 1: High Priority (Core Services)
1. **Nextcloud** - Most benefits from PostgreSQL
2. **Gitea** - Git operations need reliable database

### Phase 2: Medium Priority (Supporting Services)  
3. **Grafana** - Better dashboard management
4. **Authelia** - Security component

### Phase 3: Optional
5. **Vaultwarden** - Only if concerned about SQLite reliability
6. **Uptime-Kuma** - Low priority, SQLite works fine

---

## Common Patterns & Templates

### Standard Vault Template for Database Password
```hcl
vault {}

template {
  destination = "secrets/db.env"
  env         = true
  data        = <<EOH
DB_PASSWORD={{ with secret "secret/data/postgres/<service>" }}{{ .Data.data.password }}{{ end }}
EOH
}
```

### Standard PostgreSQL Connection String
```
postgresql://<username>:${DB_PASSWORD}@postgresql.service.consul:5432/<database>
```

### Standard Environment Variable Pattern
```hcl
env {
  DB_TYPE = "postgres"
  DB_HOST = "postgresql.service.consul"
  DB_PORT = "5432"
  DB_NAME = "<database>"
  DB_USER = "<username>"
  # DB_PASSWORD from Vault template
  DB_SSL_MODE = "disable"
}
```

---

## Adding New Databases to PostgreSQL

If you need to add a new database (e.g., for Vaultwarden):

1. **Generate a strong password**:
   ```bash
   openssl rand -base64 32
   ```

2. **Create database and user** (SSH to PostgreSQL client):
   ```bash
   nomad alloc exec -task postgres <postgres-alloc-id> \
     psql -U postgres -c "CREATE DATABASE <dbname>;"
   
   nomad alloc exec -task postgres <postgres-alloc-id> \
     psql -U postgres -c "CREATE USER <username> WITH ENCRYPTED PASSWORD '<password>';"
   
   nomad alloc exec -task postgres <postgres-alloc-id> \
     psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE <dbname> TO <username>;"
   
   nomad alloc exec -task postgres <postgres-alloc-id> \
     psql -U postgres -d <dbname> -c "GRANT ALL ON SCHEMA public TO <username>;"
   ```

3. **Store password in Vault**:
   ```bash
   vault kv put secret/postgres/<service> password="<password>"
   ```

4. **Update PostgreSQL init script** (optional, for future rebuilds):
   Edit `jobs/services/postgresql.nomad.hcl` to add new database section

---

## Troubleshooting

### Connection Refused
- Verify PostgreSQL is running: `nomad job status postgresql`
- Check Consul service: `consul catalog service postgresql`
- Test connectivity: `nc -zv postgresql.service.consul 5432`

### Authentication Failed
- Verify Vault secret exists: `vault kv get secret/postgres/<service>`
- Check password in allocation: `nomad alloc exec <alloc-id> env | grep PASSWORD`
- Verify user exists in PostgreSQL:
  ```bash
  nomad alloc exec -task postgres <pg-alloc-id> \
    psql -U postgres -c "\du"
  ```

### Template Not Rendering
- Verify `vault {}` block present in task
- Check JWT auth working: `vault auth list`
- Check allocation events: `nomad alloc status <alloc-id>`
- Verify policy allows access: `vault policy read nomad-workloads`

### Database Not Found
- List databases:
  ```bash
  nomad alloc exec -task postgres <pg-alloc-id> \
    psql -U postgres -c "\l"
  ```
- Create if missing (see "Adding New Databases" section)

### Migration Data Loss
- Always backup SQLite before migration
- Test with non-critical service first
- Verify data in PostgreSQL before removing SQLite files

---

## Success Criteria

A successful migration means:
- ✅ Service starts without errors
- ✅ Web UI accessible
- ✅ Database connection established (check logs)
- ✅ All existing data migrated (if applicable)
- ✅ Functionality tests pass
- ✅ No errors in `nomad alloc logs`
- ✅ PostgreSQL shows active connections: `SELECT * FROM pg_stat_activity;`

---

## Next Steps After All Migrations

1. **Remove SQLite files** from NAS volumes (after 30-day retention)
2. **Update documentation** to reflect PostgreSQL usage
3. **Configure automated backups** (already handled by postgres-backup sidecar)
4. **Monitor database performance** in Grafana
5. **Set up connection pooling** if needed (PgBouncer)
6. **Enable PostgreSQL metrics** in Prometheus
7. **Document restore procedures** for disaster recovery

---

## References

- PostgreSQL Job: `jobs/services/postgresql.nomad.hcl`
- Vault Integration Docs: `docs/VAULT_POSTGRES_FIX.md`
- Vault Policy: Run `vault policy read nomad-workloads`
- Existing Secrets: `vault kv list secret/postgres/`
- JWT Config Playbook: `ansible/playbooks/configure-vault-jwt-auth.yml`
