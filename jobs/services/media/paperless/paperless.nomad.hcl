job "paperless-ngx" {
  datacenters = ["dc1"]
  type        = "service"

  group "paperless" {
    count = 1

    network {
      mode = "host"
      port "http" {
        static = 8086
      }
      port "db" {
        static = 5435
      }
      port "redis" {
        static = 6380
      }
    }

    volume "paperless_data" {
      type      = "host"
      read_only = false
      source    = "paperless_data"
    }

    volume "paperless_media" {
      type      = "host"
      read_only = false
      source    = "paperless_media"
    }

    volume "paperless_consume" {
      type      = "host"
      read_only = false
      source    = "paperless_consume"
    }

    volume "paperless_export" {
      type      = "host"
      read_only = false
      source    = "paperless_export"
    }

    volume "paperless_postgres_data" {
      type      = "host"
      read_only = false
      source    = "paperless_postgres_data"
    }

    # PostgreSQL database
    task "postgres" {
      driver = "docker"

      vault {}

      config {
        image        = "postgres:16-alpine"
        network_mode = "host"
        ports        = ["db"]
      }

      volume_mount {
        volume      = "paperless_postgres_data"
        destination = "/var/lib/postgresql/data"
      }

      template {
        destination = "secrets/postgres.env"
        env         = true
        data        = <<EOH
POSTGRES_DB=paperless
POSTGRES_USER=paperless
POSTGRES_PASSWORD={{ with secret "secret/data/postgres/paperless" }}{{ .Data.data.password }}{{ end }}
EOH
      }

      env {
        PGDATA = "/var/lib/postgresql/data/pgdata"
      }

      resources {
        cpu    = 500
        memory = 256
      }

      service {
        name = "paperless-postgres"
        port = "db"
        tags = ["database", "postgres"]
        
        check {
          type     = "tcp"
          interval = "30s"
          timeout  = "5s"
        }
      }
    }

    # Redis task (required for Paperless)
    task "redis" {
      driver = "docker"

      config {
        image        = "redis:7-alpine"
        network_mode = "host"
        ports        = ["redis"]
        args         = ["redis-server", "--port", "6380"]
      }

      resources {
        cpu    = 200
        memory = 128
      }

      service {
        name = "paperless-redis"
        port = "redis"
        check {
          type     = "tcp"
          interval = "30s"
          timeout  = "5s"
        }
      }
    }

    # Paperless-ngx application
    task "paperless" {
      driver = "docker"

      vault {}

      config {
        image        = "ghcr.io/paperless-ngx/paperless-ngx:latest"
        network_mode = "host"
        ports        = ["http"]
      }

      volume_mount {
        volume      = "paperless_data"
        destination = "/usr/src/paperless/data"
      }

      volume_mount {
        volume      = "paperless_media"
        destination = "/usr/src/paperless/media"
      }

      volume_mount {
        volume      = "paperless_consume"
        destination = "/usr/src/paperless/consume"
      }

      volume_mount {
        volume      = "paperless_export"
        destination = "/usr/src/paperless/export"
      }

      # Vault template for database and secrets
      template {
        destination = "secrets/paperless.env"
        env         = true
        data        = <<EOH
# Database configuration
PAPERLESS_DBHOST=localhost
PAPERLESS_DBPORT=5435
PAPERLESS_DBNAME=paperless
PAPERLESS_DBUSER=paperless
PAPERLESS_DBPASS={{ with secret "secret/data/postgres/paperless" }}{{ .Data.data.password }}{{ end }}

# Secret key
PAPERLESS_SECRET_KEY={{ with secret "secret/data/paperless/secret" }}{{ .Data.data.value }}{{ end }}

# Admin credentials (for initial setup)
PAPERLESS_ADMIN_USER={{ with secret "secret/data/paperless/admin" }}{{ .Data.data.username }}{{ end }}
PAPERLESS_ADMIN_PASSWORD={{ with secret "secret/data/paperless/admin" }}{{ .Data.data.password }}{{ end }}
EOH
      }

      env {
        # Redis configuration
        PAPERLESS_REDIS = "redis://localhost:6380"

        # Application URL
        PAPERLESS_URL = "https://paperless.lab.hartr.net"

        # Port configuration
        PAPERLESS_PORT = "8086"

        # OCR settings
        PAPERLESS_OCR_LANGUAGE = "eng"
        PAPERLESS_OCR_MODE = "skip"  # Options: skip, redo, force

        # Time zone
        PAPERLESS_TIME_ZONE = "America/Chicago"

        # User map for file permissions
        USERMAP_UID = "1000"
        USERMAP_GID = "1000"

        # Consumption settings
        PAPERLESS_CONSUMER_POLLING = "60"
        PAPERLESS_CONSUMER_DELETE_DUPLICATES = "true"
        PAPERLESS_CONSUMER_RECURSIVE = "true"

        # Tika and Gotenberg (disabled for resource efficiency)
        PAPERLESS_TIKA_ENABLED = "false"
        PAPERLESS_ENABLE_HTTP_REMOTE_USER = "false"
      }

      resources {
        cpu    = 1000
        memory = 1024
      }

      service {
        name = "paperless-ngx"
        port = "http"
        tags = [
          "document-management",
          "ocr",
          "traefik.enable=true",
          "traefik.http.routers.paperless.rule=Host(`paperless.lab.hartr.net`)",
          "traefik.http.routers.paperless.entrypoints=websecure",
          "traefik.http.routers.paperless.tls=true",
          "traefik.http.routers.paperless.tls.certresolver=letsencrypt",
        ]
        check {
          type     = "http"
          path     = "/"
          interval = "30s"
          timeout  = "5s"
        }
      }
    }
  }
}
