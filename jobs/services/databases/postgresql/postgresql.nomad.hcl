job "postgresql" {
  datacenters = ["dc1"]
  type        = "service"

  spread {
    attribute = "${node.unique.name}"
  }

  constraint {
    attribute = "${node.unique.name}"
    value     = "dev-nomad-client-1"
  }

  group "postgres" {
    count = 1

    network {
      mode = "host"
      port "db" {
        static = 5432
      }
    }

    volume "postgres_data" {
      type      = "host"
      read_only = false
      source    = "postgres_data"
    }

    task "postgres" {
      driver = "docker"

      # Enable Vault workload identity for secrets access
      vault {}

      config {
        image        = "postgres:16-alpine"
        network_mode = "host"
        ports        = ["db"]
        privileged   = true
      }

      volume_mount {
        volume      = "postgres_data"
        destination = "/var/lib/postgresql/data"
      }

      # Vault template for PostgreSQL admin password
      template {
        destination = "secrets/postgres.env"
        env         = true
        change_mode = "noop"
        data        = <<EOH
# PostgreSQL superuser password
POSTGRES_PASSWORD={{ with secret "secret/data/postgres/admin" }}{{ .Data.data.password }}{{ end }}
EOH
      }

      env {
        POSTGRES_USER     = "postgres"
        POSTGRES_DB       = "postgres"
        PGDATA            = "/var/lib/postgresql/data/pgdata"
        
        # Performance tuning
        POSTGRES_INITDB_ARGS = "--encoding=UTF8 --locale=C"
        
        # Logging
        POSTGRES_HOST_AUTH_METHOD = "scram-sha-256"
      }

      resources {
        cpu        = 500
        memory     = 256
        memory_max = 512
      }

      service {
        name = "postgresql"
        port = "db"
        tags = [
          "database",
          "postgres",
        ]
        
        check {
          type     = "script"
          name     = "postgres-ready"
          command  = "pg_isready"
          args     = ["-h", "localhost", "-U", "postgres"]
          interval = "10s"
          timeout  = "5s"
        }

        check {
          type     = "script"
          name     = "postgres-alive"
          command  = "/bin/sh"
          args     = [
            "-c",
            "PGPASSWORD=$POSTGRES_PASSWORD psql -h localhost -U postgres -c 'SELECT 1'"
          ]
          interval = "30s"
          timeout  = "10s"
        }
      }
    }

    # Database initialization task - runs idempotently on every deployment
    task "init-databases" {
      driver = "docker"

      # Enable Vault workload identity for secrets access
      vault {}

      lifecycle {
        hook    = "poststart"
        sidecar = false
      }

      config {
        image        = "postgres:16-alpine"
        network_mode = "host"
        command      = "/bin/sh"
        args         = ["${NOMAD_TASK_DIR}/init-databases.sh"]
      }

      # Vault template for PostgreSQL admin password
      template {
        destination = "secrets/postgres.env"
        env         = true
        change_mode = "noop"
        data        = <<EOH
POSTGRES_PASSWORD={{ with secret "secret/data/postgres/admin" }}{{ .Data.data.password }}{{ end }}
EOH
      }

      # Idempotent initialization script - safe to run multiple times
      template {
        destination = "local/init-databases.sh"
        perms       = "755"
        data        = <<EOH
#!/bin/sh
set -e

echo "Waiting for PostgreSQL to be ready..."
until pg_isready -h localhost -U postgres; do
  sleep 2
done

echo "PostgreSQL is ready. Running database initialization..."

# Run idempotent database setup
PGPASSWORD=$POSTGRES_PASSWORD psql -h localhost -U postgres <<-'EOSQL'
    -- FreshRSS
    SELECT 'CREATE DATABASE freshrss' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'freshrss')\gexec
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'freshrss') THEN
        CREATE USER freshrss WITH ENCRYPTED PASSWORD '{{ with secret "secret/data/postgres/freshrss" }}{{ .Data.data.password }}{{ end }}';
      END IF;
    END
    $$;
    GRANT ALL PRIVILEGES ON DATABASE freshrss TO freshrss;
    \c freshrss
    GRANT ALL ON SCHEMA public TO freshrss;

    -- Gitea
    \c postgres
    SELECT 'CREATE DATABASE gitea' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'gitea')\gexec
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'gitea') THEN
        CREATE USER gitea WITH ENCRYPTED PASSWORD '{{ with secret "secret/data/postgres/gitea" }}{{ .Data.data.password }}{{ end }}';
      END IF;
    END
    $$;
    GRANT ALL PRIVILEGES ON DATABASE gitea TO gitea;
    \c gitea
    GRANT ALL ON SCHEMA public TO gitea;

    -- Authelia
    \c postgres
    SELECT 'CREATE DATABASE authelia' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'authelia')\gexec
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'authelia') THEN
        CREATE USER authelia WITH ENCRYPTED PASSWORD '{{ with secret "secret/data/postgres/authelia" }}{{ .Data.data.password }}{{ end }}';
      END IF;
    END
    $$;
    GRANT ALL PRIVILEGES ON DATABASE authelia TO authelia;
    \c authelia
    GRANT ALL ON SCHEMA public TO authelia;

    -- Grafana
    \c postgres
    SELECT 'CREATE DATABASE grafana' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'grafana')\gexec
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'grafana') THEN
        CREATE USER grafana WITH ENCRYPTED PASSWORD '{{ with secret "secret/data/postgres/grafana" }}{{ .Data.data.password }}{{ end }}';
      END IF;
    END
    $$;
    GRANT ALL PRIVILEGES ON DATABASE grafana TO grafana;
    \c grafana
    GRANT ALL ON SCHEMA public TO grafana;

    -- Speedtest Tracker
    \c postgres
    SELECT 'CREATE DATABASE speedtest' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'speedtest')\gexec
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'speedtest') THEN
        CREATE USER speedtest WITH ENCRYPTED PASSWORD '{{ with secret "secret/data/postgres/speedtest" }}{{ .Data.data.password }}{{ end }}';
      END IF;
    END
    $$;
    GRANT ALL PRIVILEGES ON DATABASE speedtest TO speedtest;
    \c speedtest
    GRANT ALL ON SCHEMA public TO speedtest;

    -- Uptime Kuma
    \c postgres
    SELECT 'CREATE DATABASE uptimekuma' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'uptimekuma')\gexec
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'uptimekuma') THEN
        CREATE USER uptimekuma WITH ENCRYPTED PASSWORD '{{ with secret "secret/data/postgres/uptimekuma" }}{{ .Data.data.password }}{{ end }}';
      END IF;
    END
    $$;
    GRANT ALL PRIVILEGES ON DATABASE uptimekuma TO uptimekuma;
    \c uptimekuma
    GRANT ALL ON SCHEMA public TO uptimekuma;

    -- Vaultwarden
    \c postgres
    SELECT 'CREATE DATABASE vaultwarden' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'vaultwarden')\gexec
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'vaultwarden') THEN
        CREATE USER vaultwarden WITH ENCRYPTED PASSWORD '{{ with secret "secret/data/postgres/vaultwarden" }}{{ .Data.data.password }}{{ end }}';
      END IF;
    END
    $$;
    GRANT ALL PRIVILEGES ON DATABASE vaultwarden TO vaultwarden;
    \c vaultwarden
    GRANT ALL ON SCHEMA public TO vaultwarden;
EOSQL

echo "Database initialization completed successfully!"
EOH
      }

      resources {
        cpu        = 200
        memory     = 64
        memory_max = 128
      }
    }

    # Backup task (runs daily)
    task "postgres-backup" {
      driver = "docker"

      # Enable Vault workload identity for secrets access
      vault {}

      lifecycle {
        hook    = "poststart"
        sidecar = true
      }

      config {
        image   = "postgres:16-alpine"
        command = "sh"
        args = ["-c", <<EOF
# Wait for PostgreSQL to be ready
until pg_isready -h localhost -U postgres; do
  echo "Waiting for PostgreSQL to start..."
  sleep 5
done

echo "Starting backup loop..."
while true; do
  # Run daily backup at 2 AM
  CURRENT_HOUR=$(date +%H)
  if [ "$CURRENT_HOUR" = "02" ]; then
    echo "Running daily backup at $(date)"
    BACKUP_FILE="/backups/postgres_backup_$(date +%Y%m%d_%H%M%S).sql"
    
    PGPASSWORD=$POSTGRES_PASSWORD pg_dumpall -h localhost -U postgres > $BACKUP_FILE
    
    if [ $? -eq 0 ]; then
      echo "Backup completed: $BACKUP_FILE"
      # Keep only last 7 days of backups
      find /backups -name "postgres_backup_*.sql" -mtime +7 -delete
    else
      echo "Backup failed!"
    fi
    
    # Sleep for 23 hours to avoid running multiple times in the same hour
    sleep 82800
  fi
  
  # Check every hour
  sleep 3600
done
EOF
        ]

        volumes = [
          "${NOMAD_ALLOC_DIR}/../postgres_data/backups:/backups"
        ]
      }

      template {
        destination = "secrets/postgres.env"
        env         = true
        change_mode = "noop"
        data        = <<EOH
POSTGRES_PASSWORD={{ with secret "secret/data/postgres/admin" }}{{ .Data.data.password }}{{ end }}
EOH
      }

      resources {
        cpu        = 100
        memory     = 64
        memory_max = 128
      }
    }
  }
}
