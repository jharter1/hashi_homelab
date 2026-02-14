# PostgreSQL Automated Initialization

This document explains the automated, idempotent database initialization system for PostgreSQL services.

## Overview

The PostgreSQL job now includes an **automated initialization task** (`init-databases`) that runs on every deployment to ensure all required databases and users exist. The system is **fully idempotent** - safe to run multiple times without errors.

## How It Works

### Initialization Task Architecture

```hcl
task "init-databases" {
  lifecycle {
    hook    = "poststart"  # Runs after PostgreSQL starts
    sidecar = false        # Exits after completion
  }
}
```

**Execution Flow:**
1. PostgreSQL main task starts
2. `init-databases` task waits for PostgreSQL to be ready (`pg_isready`)
3. Runs idempotent SQL script that creates missing databases/users
4. Task completes and exits

### Idempotency Guarantees

The script uses PostgreSQL's conditional creation syntax:

```sql
-- Database creation (only if not exists)
SELECT 'CREATE DATABASE dbname' 
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'dbname')\gexec

-- User creation (only if not exists)
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'username') THEN
    CREATE USER username WITH ENCRYPTED PASSWORD 'password';
  END IF;
END
$$;

-- Permissions (always grant - idempotent)
GRANT ALL PRIVILEGES ON DATABASE dbname TO username;
```

## Adding a New Service

To add database support for a new service:

### 1. Create Vault Secret

```fish
source .credentials
vault kv put secret/postgres/myservice password="$(openssl rand -base64 32)"
```

### 2. Add Database Entry to PostgreSQL Job

Edit `jobs/services/databases/postgresql/postgresql.nomad.hcl` and add to the `init-databases` task template:

```sql
-- My Service
\c postgres
SELECT 'CREATE DATABASE myservice' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'myservice')\gexec
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'myservice') THEN
    CREATE USER myservice WITH ENCRYPTED PASSWORD '{{ with secret "secret/data/postgres/myservice" }}{{ .Data.data.password }}{{ end }}';
  END IF;
END
$$;
GRANT ALL PRIVILEGES ON DATABASE myservice TO myservice;
\c myservice
GRANT ALL ON SCHEMA public TO myservice;
```

### 3. Redeploy PostgreSQL

```fish
source .credentials
nomad job run jobs/services/databases/postgresql/postgresql.nomad.hcl
```

The `init-databases` task will automatically:
- Create the new database and user
- Leave existing databases untouched
- Grant appropriate permissions

### 4. Configure Your Service

Use Vault template in your service's Nomad job:

```hcl
template {
  destination = "secrets/db.env"
  env         = true
  data        = <<EOH
DB_PASSWORD={{ with secret "secret/data/postgres/myservice" }}{{ .Data.data.password }}{{ end }}
DB_HOST={{ range service "postgresql" }}{{ .Address }}{{ end }}
EOH
}

env {
  DB_CONNECTION = "pgsql"
  DB_PORT = "5432"
  DB_DATABASE = "myservice"
  DB_USERNAME = "myservice"
}
```

## Current Services

The following databases are automatically initialized:

| Service       | Database      | User          | Vault Path                   |
|---------------|---------------|---------------|------------------------------|
| Authelia      | authelia      | authelia      | secret/postgres/authelia     |
| FreshRSS      | freshrss      | freshrss      | secret/postgres/freshrss     |
| Gitea         | gitea         | gitea         | secret/postgres/gitea        |
| Grafana       | grafana       | grafana       | secret/postgres/grafana      |
| Speedtest     | speedtest     | speedtest     | secret/postgres/speedtest    |
| Uptime Kuma   | uptimekuma   | uptimekuma    | secret/postgres/uptimekuma   |
| Vaultwarden   | vaultwarden   | vaultwarden   | secret/postgres/vaultwarden  |

## Verification

### Check Init Task Logs

```fish
# Get latest PostgreSQL allocation ID
ALLOC_ID=$(nomad job status postgresql | grep running | head -1 | awk '{print $1}')

# View initialization logs
nomad alloc logs $ALLOC_ID init-databases
```

Expected output:
```
Waiting for PostgreSQL to be ready...
localhost:5432 - accepting connections
PostgreSQL is ready. Running database initialization...
CREATE DATABASE (or skipped if exists)
DO
GRANT
...
Database initialization completed successfully!
```

### List All Databases

```fish
ssh ubuntu@10.0.0.60 "sudo docker ps | grep postgres | awk '{print \$1}' | \\
  xargs sudo docker exec -i psql -U postgres -c '\\l'"
```

### Test Database Connection

```fish
# Get password from Vault
PASSWORD=$(vault kv get -field=password secret/postgres/myservice)

# Test connection
ssh ubuntu@10.0.0.60 "PGPASSWORD='$PASSWORD' sudo docker exec -i \$(sudo docker ps | grep postgres | awk '{print \$1}') \\
  psql -U myservice -d myservice -c 'SELECT current_database();'"
```

## Troubleshooting

### Init Task Failed

Check init-databases task logs:
```fish
nomad alloc status <alloc-id>
nomad alloc logs <alloc-id> init-databases
```

Common issues:
- **Vault secret missing**: Ensure password exists in Vault
- **PostgreSQL not ready**: Init task waits indefinitely - check postgres task health
- **Permission issues**: Verify postgres admin password is correct

### Database Already Exists But Missing Permissions

The init script always re-grants permissions, so simply redeploy PostgreSQL:
```fish
nomad job run jobs/services/databases/postgresql/postgresql.nomad.hcl
```

### Service Can't Connect to Database

1. Verify database exists:
   ```fish
   ssh ubuntu@10.0.0.60 "sudo docker exec -i \$(sudo docker ps | grep postgres | awk '{print \$1}') \\
     psql -U postgres -c '\\l' | grep myservice"
   ```

2. Verify user exists:
   ```fish
   ssh ubuntu@10.0.0.60 "sudo docker exec -i \$(sudo docker ps | grep postgres | awk '{print \$1}') \\
     psql -U postgres -c '\\du myservice'"
   ```

3. Test password from Vault:
   ```fish
   PASSWORD=$(vault kv get -field=password secret/postgres/myservice)
   ssh ubuntu@10.0.0.60 "PGPASSWORD='$PASSWORD' sudo docker exec -i \$(sudo docker ps | grep postgres | awk '{print \$1}') \\
     psql -U myservice -d myservice -c 'SELECT version();'"
   ```

## Benefits

✅ **Zero Manual Intervention**: No more SSH into containers to create databases  
✅ **Fully Idempotent**: Safe to run multiple times, creates only what's missing  
✅ **Self-Healing**: Redeploy PostgreSQL to fix missing databases/permissions  
✅ **Easy to Extend**: Add new services by editing one file  
✅ **Vault Integration**: Passwords automatically retrieved securely  
✅ **Deployment Verification**: Task logs show exactly what was created  

## Migration from Manual Setup

If you previously created databases manually, the init script will:
1. Detect existing databases (skip creation)
2. Detect existing users (skip creation)
3. Re-grant permissions (idempotent, ensures correct permissions)

No migration needed - just redeploy and verify logs!
