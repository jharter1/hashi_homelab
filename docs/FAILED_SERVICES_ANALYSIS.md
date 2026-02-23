# Failed Services Analysis & Recovery Plan
**Date**: February 22, 2026  
**Root Cause**: NFS volume permission issues preventing container write access

## Summary

9 services are currently in failed/pending status. The root cause is **NFS volume permissions** - containers cannot write to `/mnt/nas/*_data` directories due to ownership mismatches and NFS root_squash restrictions.

**Current Status by Service:**
- ✅ **Bookstack**: RUNNING (MariaDB sidecar unaffected)
- ❌ **PostgreSQL** (shared): FAILED - Permission denied on `/mnt/nas/postgres_data`
- ❌ **Prometheus**: FAILED - Permission denied on `/mnt/nas/prometheus_data`
- ❌ **Trilium**: FAILED - Permission denied on `/mnt/nas/trilium_data`
- ❌ **Speedtest**: FAILED - Can't connect to shared PostgreSQL
- ❌ **Gitea**: FAILED - Permission denied + Can't connect to shared PostgreSQL
- ❌ **Authelia**: FAILED - Can't connect to shared PostgreSQL + Permission denied on `/mnt/nas/authelia_data`
- ❌ **Linkwarden**: FAILED - Sidecar PostgreSQL permission denied on `/mnt/nas/linkwarden_postgres_data`
- ❌ **Wallabag**: FAILED - Sidecar PostgreSQL permission denied on `/mnt/nas/wallabag_postgres_data`

---

## Detailed Service Analysis

### 1. PostgreSQL (Shared Database) ❌
**Current Config**: Standalone service on port 5432  
**Volume**: `/mnt/nas/postgres_data` → `/var/lib/postgresql/data`  
**Database Support**: Required (is the database)  
**Current Issue**: 
```
chmod: /var/lib/postgresql/data/pgdata: Operation not permitted
```

**Root Cause**: PostgreSQL container runs as UID 70 (postgres user), but NFS volume owned by root (UID 0). Cannot change ownership due to NFS root_squash.

**Consumers**: Gitea, Authelia, Speedtest, FreshRSS, Grafana

**Recommended Solution**: 
1. **Short-term**: Run PostgreSQL container with `privileged = true` + mount with `uid=70` mount option OR
2. **Long-term**: Each service gets its own sidecar PostgreSQL (eliminates single point of failure)

**SQLite Alternative**: N/A (is the database)

---

### 2. Prometheus ❌
**Current Config**: Standalone monitoring service  
**Volume**: `/mnt/nas/prometheus_data` → `/prometheus`  
**Database Support**: None (uses TSDB on filesystem)  
**Current Issue**:
```
panic: Unable to create mmap-ed active query log
open /prometheus/queries.active: permission denied
```

**Root Cause**: Prometheus container runs as UID 65534 (nobody), volume owned by nobody:nogroup but still getting permission denied (likely subdirectory issue).

**Recommended Solution**: 
1. Remove `privileged = true` flag (not needed)
2. Add `user = "65534:65534"` to Docker config
3. Ensure `/mnt/nas/prometheus_data` is 777 or owned by 65534:65534
4. Consider using `--storage.tsdb.no-lockfile` arg (already set)

**Migration Priority**: **HIGH** (critical monitoring service)

**SQLite Alternative**: N/A (uses TSDB)

---

### 3. Trilium ❌
**Current Config**: Note-taking application  
**Volume**: `/mnt/nas/trilium_data` → `/home/node/trilium-data`  
**Database Support**: **Built-in SQLite** (already using it!)  
**Current Issue**:
```
Error: EACCES: permission denied, open '/home/node/trilium-data/log/trilium-2026-02-22.log'
```

**Root Cause**: Container runs as `node` user (UID 1000), but volume is created as root or wrong ownership.

**Recommended Solution**:
1. Keep existing SQLite configuration (no database migration needed)
2. Add `user = "1000:1000"` to Docker config
3. Ensure `/mnt/nas/trilium_data` is owned by 1000:1000 or use 777 permissions

**Migration Priority**: **LOW** (already using SQLite, just needs permission fix)

**SQLite Alternative**: **Already using SQLite** ✓

---

### 4. Speedtest-Tracker ❌
**Current Config**: Using shared PostgreSQL  
**Volume**: `/mnt/nas/speedtest_data` → `/config`  
**Database Support**: PostgreSQL or **SQLite/MySQL**  
**Current Issue**:
```
SQLSTATE[08006] [7] connection to server at "127.0.0.1", port 5432 failed: Connection refused
```

**Root Cause**: Trying to connect to shared PostgreSQL which is down.

**Recommended Solution**:
**Option A - SQLite (Recommended)**:
- Change `DB_CONNECTION` from `pgsql` to `sqlite`
- Set `DB_DATABASE` to `/config/database/speedtest.db`
- Remove all PostgreSQL-related env vars
- Remove Vault template for DB password
- Simple, self-contained

**Option B - Sidecar PostgreSQL**:
- Add sidecar postgres task on port 5433
- Similar to Linkwarden/Wallabag pattern
- Requires fixing sidecar permission issues first

**Migration Priority**: **MEDIUM** (useful but not critical)

**SQLite Alternative**: **Yes - supports SQLite natively** ✓

---

### 5. Gitea ❌
**Current Config**: Using shared PostgreSQL  
**Volume**: `/mnt/nas/gitea_data` → `/data`  
**Database Support**: PostgreSQL, MySQL, **SQLite**  
**Current Issue**:
```
Permission denied on /data/git/.ssh
Cannot connect to PostgreSQL
```

**Root Cause**: 
1. Volume permission issues (runs as UID 1000 but volume owned incorrectly)
2. Shared PostgreSQL is down

**Recommended Solution**:
**Option A - Sidecar PostgreSQL (Recommended for production)**:
- Add sidecar postgres task on port 5433
- Keeps data in proper relational DB
- Fix sidecar volume permissions (see Pattern below)
- Gitea is a larger app, benefits from PostgreSQL

**Option B - SQLite**:
- Change `GITEA__database__DB_TYPE` to `sqlite3`
- Set `GITEA__database__PATH` to `/data/gitea/gitea.db`
- Remove PostgreSQL config and Vault template
- Simpler but less performant for multi-user scenarios

**Migration Priority**: **HIGH** (development-critical service)

**SQLite Alternative**: **Yes - supports SQLite3** ✓

---

### 6. Authelia ❌
**Current Config**: Using shared PostgreSQL + Redis  
**Volume**: `/mnt/nas/authelia_data` → `/data`  
**Database Support**: PostgreSQL, MySQL, **SQLite**  
**Current Issue**:
```
error pinging database: failed to connect to postgresql
open /data/notification.txt: permission denied
```

**Root Cause**:
1. Shared PostgreSQL is down
2. Volume permission issues

**Recommended Solution**:
**Option A - SQLite (Recommended)**:
- Change storage backend from `postgres:` to `local:` in configuration
```yaml
storage:
  local:
    path: /data/db.sqlite3
```
- Remove PostgreSQL connection details
- Remove `postgres/authelia` Vault secret dependency
- Simpler, self-contained, perfect for single-node auth
- Keep Redis for session storage (already working)

**Option B - Sidecar PostgreSQL**:
- Add sidecar postgres if you want backup/replication capabilities
- More complex, requires fixing sidecar permissions first

**Migration Priority**: **CRITICAL** (blocks access to all protected services)

**SQLite Alternative**: **Yes - supports SQLite via `local` storage** ✓

---

### 7. Linkwarden ❌
**Current Config**: **Already has sidecar PostgreSQL on port 5433**  
**Volume**: 
- `/mnt/nas/linkwarden_data` → `/data/data`
- `/mnt/nas/linkwarden_postgres_data` → `/var/lib/postgresql/data` (sidecar)

**Database Support**: **PostgreSQL required** (NextJS/Prisma app)  
**Current Issue**:
```
Sibling Task Failed: Task's sibling "postgres" failed
Exit Code: 1 (postgres sidecar failing due to permissions)
```

**Root Cause**: Sidecar PostgreSQL cannot write to `/mnt/nas/linkwarden_postgres_data` due to permission denied (same as shared PostgreSQL issue).

**Recommended Solution**:
1. **Fix sidecar volume permissions** (see Pattern below)
2. Already has correct architecture (sidecar DB)
3. No migration needed, just permission fix

**Migration Priority**: **MEDIUM** (sidecar already configured, just needs permission fix)

**SQLite Alternative**: **No - requires PostgreSQL for Prisma**

---

### 8. Wallabag ❌
**Current Config**: **Already has sidecar PostgreSQL on port 5434**  
**Volume**:
- `/mnt/nas/wallabag_data` → `/var/www/wallabag/data`
- `/mnt/nas/wallabag_images` → `/var/www/wallabag/web/assets/images`
- `/mnt/nas/wallabag_postgres_data` → `/var/lib/postgresql/data` (sidecar)

**Database Support**: PostgreSQL, MySQL, **SQLite** (via Doctrine ORM)  
**Current Issue**:
```
Sibling Task Failed: Task's sibling "postgres" failed
Exit Code: 1 (postgres sidecar failing due to permissions)
```

**Root Cause**: Same as Linkwarden - sidecar PostgreSQL permission denied.

**Recommended Solution**:
**Option A - Fix Sidecar PostgreSQL (Current approach)**:
1. Fix sidecar volume permissions
2. Keep existing configuration

**Option B - Migrate to SQLite**:
1. Remove sidecar postgres task
2. Change database driver to SQLite:
```env
SYMFONY__ENV__DATABASE_DRIVER=pdo_sqlite
SYMFONY__ENV__DATABASE_PATH=%kernel.root_dir%/../data/db/wallabag.db
```
3. Simpler, eliminates sidecar complexity
4. Wallabag is typically single-user, SQLite is fine

**Migration Priority**: **LOW** (read-later service, non-critical)

**SQLite Alternative**: **Yes - Symfony/Doctrine supports SQLite** ✓

---

### 9. Bookstack ✅ **CURRENTLY RUNNING**
**Current Config**: **Sidecar MariaDB on port 3307**  
**Volume**:
- `/mnt/nas/bookstack_config` → `/config` (owned by ubuntu 1000:1000)
- `/mnt/nas/bookstack_mariadb_data` → `/var/lib/mysql` (owned by 999:systemd-journal)

**Database Support**: MySQL/MariaDB required (Laravel app)  
**Current Status**: **WORKING**

**Why It Works**:
- MariaDB sidecar successfully writes to its volume
- Volume owned by UID 999 which matches MariaDB container user
- Shows that **sidecar pattern CAN work with correct permissions**

**Recommended Action**: **USE AS REFERENCE** for fixing other sidecars

**SQLite Alternative**: **No - requires MySQL/MariaDB for Laravel**

---

## Permission Issue Root Cause

The NFS mount at `/mnt/nas` has **root_squash** enabled (default NFS security):
```
10.0.0.220:/mnt/HD/HD_a2/PVE-VM-Storage on /mnt/nas type nfs (rw,relatime,vers=3,...)
```

**Problem**: Containers running as non-root users cannot create directories or change ownership in NFS volumes, even with `privileged = true`.

**Current Ownership Issues**:
```
/mnt/nas/postgres_data       → root:root (0:0)       [needs 70:70 for postgres]
/mnt/nas/prometheus_data     → nobody:nogroup (65534:65534) [but still failing]
/mnt/nas/gitea_data          → ubuntu:ubuntu (1000:1000) [correct but still failing]
/mnt/nas/authelia_data       → ubuntu:ubuntu (1000:1000) [correct but still failing]
/mnt/nas/linkwarden_postgres → root:root (0:0)       [needs 70:70]
/mnt/nas/wallabag_postgres   → root:root (0:0)       [needs 70:70]
/mnt/nas/bookstack_mariadb   → 999:systemd-journal   [WORKING ✓]
```

---

## Solutions & Patterns

### Pattern 1: Fix NFS Permissions (Infrastructure-level)
**Add to NFS fstab on clients**:
```
10.0.0.220:/mnt/HD/HD_a2/PVE-VM-Storage /mnt/nas nfs defaults,nofail,no_root_squash 0 0
```

**OR change NFS server exports** (requires NAS admin access):
```
/mnt/HD/HD_a2/PVE-VM-Storage *(rw,sync,no_subtree_check,no_root_squash,all_squash,anonuid=1000,anongid=1000)
```

⚠️ **Security Risk**: `no_root_squash` allows root on clients to own files on NFS. Only use in trusted networks.

---

### Pattern 2: Fix Sidecar PostgreSQL Permissions
**For services with sidecar postgres (Linkwarden, Wallabag, Gitea if migrated)**:

1. **Pre-create volume directory with correct ownership**:
```bash
ssh ubuntu@10.0.0.60 "sudo install -d -o 70 -g 70 -m 755 /mnt/nas/<service>_postgres_data"
```

2. **OR** use init container to fix permissions:
```hcl
task "init-perms" {
  driver = "docker"
  lifecycle {
    hook    = "prestart"
    sidecar = false
  }
  config {
    image   = "alpine:latest"
    command = "chown"
    args    = ["-R", "70:70", "/pgdata"]
  }
  volume_mount {
    volume      = "service_postgres_data"
    destination = "/pgdata"
  }
}
```

3. **OR** run postgres as root initially, then drop privileges:
```hcl
config {
  image = "postgres:16-alpine"
  user  = "0:0"  # Start as root
  entrypoint = ["/bin/sh", "-c"]
  args = ["chown -R postgres:postgres /var/lib/postgresql/data && su-exec postgres docker-entrypoint.sh postgres"]
}
```

---

### Pattern 3: Migrate to SQLite (Application-level)
**Best for**:
- Single-user or low-concurrency apps
- Services where simplicity > performance
- Eliminating single points of failure

**Services that support SQLite**:
✅ Trilium (already using)  
✅ Speedtest-Tracker  
✅ Gitea  
✅ Authelia  
✅ Wallabag  

**Services that require PostgreSQL/MySQL**:
❌ Linkwarden (Prisma requires PostgreSQL)  
❌ Bookstack (Laravel requires MySQL/MariaDB)  

---

## Recommended Migration Order

### Phase 1: Quick Wins (SQLite Migrations)
1. **Authelia** - CRITICAL, blocks all auth → Migrate to SQLite storage
2. **Speedtest** - EASY, just change env vars → Migrate to SQLite
3. **Trilium** - TRIVIAL, just fix permissions → Already using SQLite

### Phase 2: Fix Sidecar Permissions
4. **Linkwarden** - Fix postgres sidecar permissions using Pattern 2
5. **Wallabag** - Fix postgres sidecar permissions (or migrate to SQLite)

### Phase 3: Fix Critical Services
6. **Prometheus** - Fix `/mnt/nas/prometheus_data` permissions (UID 65534)
7. **Gitea** - Either sidecar postgres OR SQLite (recommend sidecar for multi-user)

### Phase 4: Shared PostgreSQL (Optional)
8. **PostgreSQL** - Either fix shared instance OR deprecate in favor of sidecars

---

## Migration Scripts Needed

### 1. Authelia → SQLite
- Update job file configuration
- Remove postgres connection from config template
- Change to `storage.local` backend
- Redeploy

### 2. Speedtest → SQLite
- Change `DB_CONNECTION` to `sqlite`
- Update job file env vars
- Remove Vault template
- Redeploy

### 3. Trilium - Permission Fix
- SSH to client: `sudo chown -R 1000:1000 /mnt/nas/trilium_data`
- OR add `user = "1000:1000"` to Docker config
- Redeploy

### 4. Prometheus - Permission Fix
- Verify ownership: `sudo chown -R 65534:65534 /mnt/nas/prometheus_data`
- Ensure `--storage.tsdb.no-lockfile` is set
- Redeploy

### 5. Linkwarden/Wallabag - Fix Sidecar
- Pre-create postgres volume: `sudo install -d -o 70 -g 70 /mnt/nas/<service>_postgres_data/pgdata`
- Ensure sidecar has `privileged = true`
- Redeploy

---

## Next Steps

1. **Review this analysis** and decide on migration strategy per service
2. **Start with Authelia** (critical) - migrate to SQLite
3. **Fix Prometheus** next (monitoring is important)
4. **Tackle easy wins** (Speedtest, Trilium)
5. **Fix sidecars** (Linkwarden, Wallabag) OR migrate Wallabag to SQLite
6. **Decide on Gitea** - sidecar vs SQLite based on usage
7. **Deprecate or fix** shared PostgreSQL

Would you like me to proceed with migrating specific services?
