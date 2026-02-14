job "wallabag" {
  datacenters = ["dc1"]
  type        = "service"

  group "wallabag" {
    count = 1

    network {
      mode = "host"
      port "http" {
        static = 8081
      }
      port "db" {
        static = 5434
      }
    }

    volume "wallabag_data" {
      type      = "host"
      read_only = false
      source    = "wallabag_data"
    }

    volume "wallabag_images" {
      type      = "host"
      read_only = false
      source    = "wallabag_images"
    }

    volume "wallabag_postgres_data" {
      type      = "host"
      read_only = false
      source    = "wallabag_postgres_data"
    }

    # PostgreSQL database
    task "postgres" {
      driver = "docker"

      # Ensure postgres is ready before wallabag starts
      lifecycle {
        hook    = "prestart"
        sidecar = true
      }

      vault {}

      config {
        image        = "postgres:16-alpine"
        network_mode = "host"
        ports        = ["db"]
        privileged   = true
      }

      volume_mount {
        volume      = "wallabag_postgres_data"
        destination = "/var/lib/postgresql/data"
      }

      template {
        destination = "secrets/postgres.env"
        env         = true
        data        = <<EOH
POSTGRES_DB=wallabag
POSTGRES_USER=wallabag
POSTGRES_PASSWORD={{ with secret "secret/data/postgres/wallabag" }}{{ .Data.data.password }}{{ end }}
EOH
      }

      env {
        PGDATA = "/var/lib/postgresql/data/pgdata"
        POSTGRES_HOST_AUTH_METHOD = "scram-sha-256"
        PGPORT = "5434"
      }

      resources {
        cpu    = 500
        memory = 256
      }

      service {
        name = "wallabag-postgres"
        port = "db"
        tags = ["database", "postgres"]
        
        check {
          type     = "tcp"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }

    # Wallabag application
    task "wallabag" {
      driver = "docker"

      vault {}

      config {
        image        = "wallabag/wallabag:latest"
        network_mode = "host"
        ports        = ["http"]
        privileged   = true
      }

      volume_mount {
        volume      = "wallabag_data"
        destination = "/var/www/wallabag/data"
      }

      volume_mount {
        volume      = "wallabag_images"
        destination = "/var/www/wallabag/web/assets/images"
      }

      # Vault template for database and secrets
      template {
        destination = "secrets/app.env"
        env         = true
        data        = <<EOH
# Database configuration
SYMFONY__ENV__DATABASE_DRIVER=pdo_pgsql
SYMFONY__ENV__DATABASE_HOST=localhost
SYMFONY__ENV__DATABASE_PORT=5434
SYMFONY__ENV__DATABASE_NAME=wallabag
SYMFONY__ENV__DATABASE_USER=wallabag
SYMFONY__ENV__DATABASE_PASSWORD={{ with secret "secret/data/postgres/wallabag" }}{{ .Data.data.password }}{{ end }}

# Application secret
SYMFONY__ENV__SECRET={{ with secret "secret/data/wallabag/secret" }}{{ .Data.data.value }}{{ end }}
EOH
      }

      env {
        # Domain configuration
        SYMFONY__ENV__DOMAIN_NAME = "https://wallabag.lab.hartr.net"

        # Mailer configuration (optional - using null for local deployment)
        SYMFONY__ENV__MAILER_DSN = "null://localhost"
        SYMFONY__ENV__FROM_EMAIL = "wallabag@lab.hartr.net"

        # Registration and user settings
        SYMFONY__ENV__FOSUSER_REGISTRATION = "false"
        SYMFONY__ENV__FOSUSER_CONFIRMATION = "false"

        # Locale settings
        SYMFONY__ENV__LOCALE = "en"

        # Port override
        SYMFONY__ENV__SERVER_NAME = "0.0.0.0:8081"
      }

      resources {
        cpu    = 500
        memory = 512
      }

      service {
        name = "wallabag"
        port = "http"
        tags = [
          "read-later",
          "articles",
          "traefik.enable=true",
          "traefik.http.routers.wallabag.rule=Host(`wallabag.lab.hartr.net`)",
          "traefik.http.routers.wallabag.entrypoints=websecure",
          "traefik.http.routers.wallabag.tls=true",
          "traefik.http.routers.wallabag.tls.certresolver=letsencrypt",
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
