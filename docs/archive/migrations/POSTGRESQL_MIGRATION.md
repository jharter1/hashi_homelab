# PostgreSQL Deployment and Migration Guide

This guide covers deploying PostgreSQL and FreshRSS to your Nomad homelab, then migrating existing SQLite-based services to PostgreSQL.

## Prerequisites

- HashiCorp Vault with secrets engine enabled
- NAS storage mounted at `/mnt/nas` on all Nomad clients
- Traefik reverse proxy running

## Part 1: Deploy PostgreSQL

### Step 1: Configure Vault Secrets

First, create the necessary secrets in Vault for PostgreSQL users:

```bash
# PostgreSQL admin password
vault kv put secret/postgres/admin password="$(openssl rand -base64 32)"

# FreshRSS database password
vault kv put secret/postgres/freshrss password="$(openssl rand -base64 32)"

# Gitea database password
vault kv put secret/postgres/gitea password="$(openssl rand -base64 32)"

# Nextcloud database password
vault kv put secret/postgres/nextcloud password="$(openssl rand -base64 32)"

# Authelia database password
vault kv put secret/postgres/authelia password="$(openssl rand -base64 32)"

# Grafana database password
vault kv put secret/postgres/grafana password="$(openssl rand -base64 32)"
```

### Step 2: Update Nomad Client Configuration

The host volumes have already been added to the Nomad client configuration. Deploy the changes:

```bash
cd ansible
ansible-playbook playbooks/clients-only.yml
```

This will:
- Create the necessary volume directories on the NAS
- Update Nomad client configuration
- Restart Nomad clients to pick up the new volumes

### Step 3: Preload Docker Images

The image-preloader has been updated to include PostgreSQL and FreshRSS. Restart the system job:

```bash
# From the Nomad UI or CLI
nomad job run jobs/system/image-preloader.nomad.hcl
```

### Step 4: Deploy PostgreSQL

```bash
nomad job run jobs/services/postgresql.nomad.hcl
```

Verify PostgreSQL is running:

```bash
nomad job status postgresql
nomad alloc logs -f <alloc-id>
```

Check the service is registered in Consul:

```bash
consul catalog services | grep postgres
```

Test database connectivity:

```bash
# Get the PostgreSQL allocation ID
ALLOC_ID=$(nomad job status postgresql | grep running | awk '{print $1}' | head -n1)

# Connect to PostgreSQL
nomad alloc exec $ALLOC_ID psql -U postgres -c '\l'
```

## Part 2: Deploy FreshRSS

### Step 1: Deploy FreshRSS

```bash
nomad job run jobs/services/freshrss.nomad.hcl
```

### Step 2: Access FreshRSS

Navigate to `http://freshrss.home` and complete the setup:

1. The database should be pre-configured via environment variables
2. Login with:
   - Email: `admin@home.local`
   - Password: `changeme`
3. **Immediately change the default password** in Settings → Profile
4. Configure your RSS feeds

## Part 3: Migrate Gitea to PostgreSQL

### Pre-Migration Checklist

- [ ] Backup current Gitea data: `tar -czf gitea-backup-$(date +%Y%m%d).tar.gz /mnt/nas/gitea/`
- [ ] Verify PostgreSQL is running and accessible
- [ ] Note current Gitea version

### Migration Steps

#### 1. Stop Gitea

```bash
nomad job stop gitea
```

#### 2. Export SQLite Database

```bash
# Access the Gitea data directory on NAS
cd /mnt/nas/gitea/gitea

# Create SQL dump from SQLite
sqlite3 gitea.db .dump > gitea-sqlite-dump.sql
```

#### 3. Convert SQLite Dump to PostgreSQL Format

The SQLite dump needs some modifications to work with PostgreSQL:

```bash
# Create a conversion script
cat > convert-to-postgres.sh << 'EOF'
#!/bin/bash
sed -e 's/PRAGMA.*;$//' \
    -e 's/BEGIN TRANSACTION;/BEGIN;/' \
    -e 's/COMMIT;/COMMIT;/' \
    -e 's/INTEGER PRIMARY KEY AUTOINCREMENT/SERIAL PRIMARY KEY/' \
    -e 's/DATETIME/TIMESTAMP/' \
    -e 's/AUTOINCREMENT//' \
    gitea-sqlite-dump.sql > gitea-postgres.sql
EOF

chmod +x convert-to-postgres.sh
./convert-to-postgres.sh
```

#### 4. Import to PostgreSQL

```bash
# Get PostgreSQL allocation ID
ALLOC_ID=$(nomad job status postgresql | grep running | awk '{print $1}' | head -n1)

# Copy the SQL file to the PostgreSQL container
nomad alloc fs put $ALLOC_ID /tmp/gitea-postgres.sql gitea-postgres.sql

# Import to PostgreSQL
nomad alloc exec $ALLOC_ID psql -U gitea -d gitea -f /tmp/gitea-postgres.sql
```

#### 5. Update Gitea Job Configuration

Update `jobs/services/gitea.nomad.hcl`:

```hcl
job "gitea" {
  datacenters = ["dc1"]
  type        = "service"

  group "gitea" {
    count = 1

    network {
      mode = "host"
      port "http" {
        static = 3000
      }
      port "ssh" {
        static = 2222
      }
    }

    volume "gitea_data" {
      type      = "host"
      read_only = false
      source    = "gitea_data"
    }

    task "gitea" {
      driver = "docker"

      config {
        image        = "gitea/gitea:latest"
        network_mode = "host"
        ports        = ["http", "ssh"]
      }

      volume_mount {
        volume      = "gitea_data"
        destination = "/data"
      }

      # Add Vault template for database password
      template {
        destination = "secrets/db.env"
        env         = true
        data        = <<EOH
GITEA__database__PASSWD={{ with secret "secret/data/postgres/gitea" }}{{ .Data.data.password }}{{ end }}
EOH
      }

      env {
        USER_UID = "1000"
        USER_GID = "1000"
        
        # PostgreSQL configuration
        GITEA__database__DB_TYPE = "postgres"
        GITEA__database__HOST = "localhost:5432"
        GITEA__database__NAME = "gitea"
        GITEA__database__USER = "gitea"
        GITEA__database__SSL_MODE = "disable"
        
        # Server configuration
        GITEA__server__DOMAIN = "gitea.home"
        GITEA__server__SSH_DOMAIN = "gitea.home"
        GITEA__server__SSH_PORT = "2222"
        GITEA__server__HTTP_PORT = "3000"
        GITEA__server__ROOT_URL = "http://gitea.home"
        GITEA__server__DISABLE_SSH = "false"
      }

      resources {
        cpu    = 500
        memory = 1024
      }

      service {
        name = "gitea-http"
        port = "http"
        tags = [
          "git",
          "development",
          "traefik.enable=true",
          "traefik.http.routers.gitea.rule=Host(`gitea.home`)",
          "traefik.http.routers.gitea.entrypoints=web",
        ]
        check {
          type     = "http"
          path     = "/api/healthz"
          interval = "10s"
          timeout  = "2s"
        }
      }

      service {
        name = "gitea-ssh"
        port = "ssh"
        tags = ["git", "ssh"]
      }
    }
  }
}
```

#### 6. Deploy Updated Gitea

```bash
nomad job run jobs/services/gitea.nomad.hcl
```

#### 7. Verify Migration

- Access `http://gitea.home`
- Login with your existing credentials
- Verify repositories are accessible
- Check that SSH clone works
- Verify user accounts and settings

## Part 4: Migrate Nextcloud to PostgreSQL

### Pre-Migration Checklist

- [ ] Backup Nextcloud: `tar -czf nextcloud-backup-$(date +%Y%m%d).tar.gz /mnt/nas/nextcloud/`
- [ ] Enable maintenance mode
- [ ] Verify PostgreSQL is running

### Migration Steps

#### 1. Enable Maintenance Mode

```bash
# Get Nextcloud allocation ID
ALLOC_ID=$(nomad job status nextcloud | grep running | awk '{print $1}' | head -n1)

# Enable maintenance mode
nomad alloc exec $ALLOC_ID php occ maintenance:mode --on
```

#### 2. Stop Nextcloud

```bash
nomad job stop nextcloud
```

#### 3. Convert Database

Nextcloud provides a built-in database conversion tool:

```bash
# Update Nextcloud job with PostgreSQL config but keep conversion script
# Create a temporary conversion job

cat > /tmp/nextcloud-convert.nomad.hcl << 'EOF'
job "nextcloud-convert" {
  datacenters = ["dc1"]
  type        = "batch"

  group "convert" {
    count = 1

    volume "nextcloud_data" {
      type      = "host"
      read_only = false
      source    = "nextcloud_data"
    }

    volume "nextcloud_config" {
      type      = "host"
      read_only = false
      source    = "nextcloud_config"
    }

    task "convert" {
      driver = "docker"

      config {
        image = "nextcloud:latest"
        command = "sh"
        args = ["-c", <<EOT
# Add PostgreSQL host to config
php occ config:system:set dbhost --value="localhost:5432"
php occ config:system:set dbtype --value="pgsql"
php occ config:system:set dbname --value="nextcloud"
php occ config:system:set dbuser --value="nextcloud"
php occ config:system:set dbpassword --value="$DB_PASSWORD"

# Run conversion
php occ db:convert-type --all-apps pgsql nextcloud localhost nextcloud

echo "Conversion complete!"
EOT
        ]
      }

      volume_mount {
        volume      = "nextcloud_data"
        destination = "/var/www/html/data"
      }

      volume_mount {
        volume      = "nextcloud_config"
        destination = "/var/www/html/config"
      }

      template {
        destination = "secrets/db.env"
        env         = true
        data        = <<EOH
DB_PASSWORD={{ with secret "secret/data/postgres/nextcloud" }}{{ .Data.data.password }}{{ end }}
EOH
      }

      resources {
        cpu    = 1000
        memory = 2048
      }
    }
  }
}
EOF

# Run conversion job
nomad job run /tmp/nextcloud-convert.nomad.hcl

# Monitor progress
nomad job status nextcloud-convert
nomad alloc logs -f <alloc-id>
```

#### 4. Update Nextcloud Job Configuration

Update `jobs/services/nextcloud.nomad.hcl`:

```hcl
job "nextcloud" {
  datacenters = ["dc1"]
  type        = "service"

  group "nextcloud" {
    count = 1

    network {
      port "http" {
        to = 80
      }
    }

    volume "nextcloud_data" {
      type      = "host"
      read_only = false
      source    = "nextcloud_data"
    }

    volume "nextcloud_config" {
      type      = "host"
      read_only = false
      source    = "nextcloud_config"
    }

    task "nextcloud" {
      driver = "docker"

      config {
        image = "nextcloud:latest"
        ports = ["http"]
      }

      volume_mount {
        volume      = "nextcloud_data"
        destination = "/var/www/html/data"
      }

      volume_mount {
        volume      = "nextcloud_config"
        destination = "/var/www/html/config"
      }

      # Vault template for database password
      template {
        destination = "secrets/db.env"
        env         = true
        data        = <<EOH
POSTGRES_HOST=localhost
POSTGRES_DB=nextcloud
POSTGRES_USER=nextcloud
POSTGRES_PASSWORD={{ with secret "secret/data/postgres/nextcloud" }}{{ .Data.data.password }}{{ end }}
EOH
      }

      env {
        # Database will be configured via config.php from conversion
        TZ = "America/New_York"
        
        # Trusted proxy
        TRUSTED_PROXIES = "10.0.0.0/24"
      }

      resources {
        cpu    = 1000
        memory = 1024
      }

      service {
        name = "nextcloud"
        port = "http"
        tags = [
          "storage",
          "file-sync",
          "traefik.enable=true",
          "traefik.http.routers.nextcloud.rule=Host(`nextcloud.home`)",
          "traefik.http.routers.nextcloud.entrypoints=web",
        ]
        check {
          type     = "http"
          path     = "/status.php"
          interval = "30s"
          timeout  = "5s"
        }
      }
    }
  }
}
```

#### 5. Deploy Updated Nextcloud

```bash
nomad job run jobs/services/nextcloud.nomad.hcl
```

#### 6. Disable Maintenance Mode

```bash
# Get new allocation ID
ALLOC_ID=$(nomad job status nextcloud | grep running | awk '{print $1}' | head -n1)

# Disable maintenance mode
nomad alloc exec $ALLOC_ID php occ maintenance:mode --off

# Run database maintenance
nomad alloc exec $ALLOC_ID php occ db:add-missing-indices
nomad alloc exec $ALLOC_id php occ db:convert-filecache-bigint
```

#### 7. Verify Migration

- Access `http://nextcloud.home`
- Login with your credentials
- Verify files are accessible
- Check that sync clients work
- Review logs for any errors

## Part 5: Other Services to Consider

### Grafana

Grafana benefits from PostgreSQL for better dashboard and alert storage:

1. Create database in PostgreSQL (already created by init script)
2. Update Grafana environment variables:
   ```
   GF_DATABASE_TYPE=postgres
   GF_DATABASE_HOST=localhost:5432
   GF_DATABASE_NAME=grafana
   GF_DATABASE_USER=grafana
   GF_DATABASE_PASSWORD=<from-vault>
   GF_DATABASE_SSL_MODE=disable
   ```

### Authelia

For centralized authentication with better session management:

1. Database already created by PostgreSQL init script
2. Update Authelia configuration to use PostgreSQL backend
3. Configure session and TOTP storage in PostgreSQL

## Backup Strategy

### PostgreSQL Backups

The PostgreSQL job includes an automatic backup task that:
- Runs daily at 2 AM
- Creates full database dumps using `pg_dumpall`
- Stores backups in `/mnt/nas/postgres/backups/`
- Retains backups for 7 days

### Manual Backup

```bash
# Get PostgreSQL allocation ID
ALLOC_ID=$(nomad job status postgresql | grep running | awk '{print $1}' | head -n1)

# Create manual backup
nomad alloc exec $ALLOC_ID pg_dumpall -U postgres > postgres-backup-$(date +%Y%m%d-%H%M%S).sql

# Or backup individual database
nomad alloc exec $ALLOC_ID pg_dump -U postgres gitea > gitea-backup-$(date +%Y%m%d-%H%M%S).sql
```

### Restore from Backup

```bash
# Get PostgreSQL allocation ID
ALLOC_ID=$(nomad job status postgresql | grep running | awk '{print $1}' | head -n1)

# Copy backup to container
nomad alloc fs put $ALLOC_ID /tmp/backup.sql postgres-backup.sql

# Restore
nomad alloc exec $ALLOC_ID psql -U postgres -f /tmp/backup.sql
```

## Monitoring

### Health Checks

All services include health checks:
- PostgreSQL: `pg_isready` and connection test
- FreshRSS: HTTP health check on `/i/`
- Gitea: API health endpoint
- Nextcloud: Status page

Monitor in Consul UI or via CLI:

```bash
consul catalog services
consul watch -type=checks -service=postgresql
```

### Performance Monitoring

Consider connecting PostgreSQL to your Prometheus/Grafana stack:

1. Install postgres_exporter
2. Configure scraping in Prometheus
3. Import PostgreSQL dashboard in Grafana

## Troubleshooting

### PostgreSQL Connection Issues

```bash
# Check PostgreSQL logs
nomad alloc logs -f <postgres-alloc-id>

# Test connection from within container
nomad alloc exec <postgres-alloc-id> psql -U postgres -c "SELECT version();"

# Check network connectivity
nomad alloc exec <app-alloc-id> nc -zv localhost 5432
```

### Database Permission Issues

```bash
# Grant all privileges on a database
nomad alloc exec <postgres-alloc-id> psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE dbname TO username;"

# Grant schema permissions
nomad alloc exec <postgres-alloc-id> psql -U postgres -d dbname -c "GRANT ALL ON SCHEMA public TO username;"
```

### FreshRSS Issues

```bash
# Check FreshRSS logs
nomad alloc logs -f <freshrss-alloc-id>

# Access FreshRSS container
nomad alloc exec -task freshrss <alloc-id> sh

# Check database connection
nomad alloc exec -task freshrss <alloc-id> php -r "new PDO('pgsql:host=localhost;dbname=freshrss', 'freshrss', getenv('DB_PASSWORD'));"
```

## Security Considerations

1. **Change Default Passwords**: Immediately change the default FreshRSS admin password
2. **Vault Access**: Ensure proper Vault policies are in place for Nomad to read secrets
3. **Network Security**: Consider restricting PostgreSQL access to localhost only
4. **SSL/TLS**: For production, enable SSL connections to PostgreSQL
5. **Regular Updates**: Keep PostgreSQL and application images updated

## Next Steps

1. Deploy additional services that can benefit from PostgreSQL
2. Set up automated backups to off-site storage
3. Configure monitoring and alerting
4. Implement SSL/TLS for Traefik endpoints
5. Consider PostgreSQL replication for high availability

## Reference

- PostgreSQL job: `jobs/services/postgresql.nomad.hcl`
- FreshRSS job: `jobs/services/freshrss.nomad.hcl`
- Gitea job: `jobs/services/gitea.nomad.hcl`
- Nextcloud job: `jobs/services/nextcloud.nomad.hcl`
- Client volumes: `ansible/roles/nomad-client/templates/nomad-client.hcl.j2`
- Image preloader: `jobs/system/image-preloader.nomad.hcl`
