job "linkwarden" {
  datacenters = ["dc1"]
  type        = "service"

  group "linkwarden" {
    count = 1

    network {
      mode = "host"
      port "http" {
        static = 3001
      }
      port "db" {
        static = 5433
      }
    }

    volume "linkwarden_data" {
      type      = "host"
      read_only = false
      source    = "linkwarden_data"
    }

    volume "linkwarden_postgres_data" {
      type      = "host"
      read_only = false
      source    = "linkwarden_postgres_data"
    }

    # PostgreSQL database
    task "postgres" {
      driver = "docker"

      # Ensure postgres is ready before linkwarden starts
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
        volume      = "linkwarden_postgres_data"
        destination = "/var/lib/postgresql/data"
      }

      template {
        destination = "secrets/postgres.env"
        env         = true
        data        = <<EOH
POSTGRES_DB=linkwarden
POSTGRES_USER=linkwarden
POSTGRES_PASSWORD={{ with secret "secret/data/postgres/linkwarden" }}{{ .Data.data.password }}{{ end }}
EOH
      }

      env {
        PGDATA = "/var/lib/postgresql/data/pgdata"
        POSTGRES_HOST_AUTH_METHOD = "scram-sha-256"
        PGPORT = "5433"
      }

      resources {
        cpu    = 500
        memory = 256
      }

      service {
        name = "linkwarden-postgres"
        port = "db"
        tags = ["database", "postgres"]
        
        check {
          type     = "tcp"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }

    # Linkwarden application
    task "linkwarden" {
      driver = "docker"

      vault {}

      config {
        image        = "ghcr.io/linkwarden/linkwarden:latest"
        network_mode = "host"
        ports        = ["http"]
        privileged   = true
      }

      # Run as user 1000 to match NFS ownership and avoid su-exec issues
      user = "1000:1000"

      volume_mount {
        volume      = "linkwarden_data"
        destination = "/data/data"
      }

      # Vault template for database credentials
      template {
        destination = "secrets/db.env"
        env         = true
        data        = <<EOH
# Database URL for PostgreSQL
DATABASE_URL=postgresql://linkwarden:{{ with secret "secret/data/postgres/linkwarden" }}{{ .Data.data.password }}{{ end }}@localhost:5433/linkwarden

# NextAuth secret (generate with: openssl rand -base64 32)
NEXTAUTH_SECRET={{ with secret "secret/data/linkwarden/nextauth" }}{{ .Data.data.secret }}{{ end }}
EOH
      }

      env {
        # Application URL
        NEXTAUTH_URL = "https://linkwarden.lab.hartr.net"

        # Disable telemetry
        NEXT_TELEMETRY_DISABLED = "1"

        # Port configuration
        PORT = "3001"
      }

      resources {
        cpu    = 500
        memory = 512
      }

      service {
        name = "linkwarden"
        port = "http"
        tags = [
          "bookmarks",
          "archiving",
          "traefik.enable=true",
          "traefik.http.routers.linkwarden.rule=Host(`linkwarden.lab.hartr.net`)",
          "traefik.http.routers.linkwarden.entrypoints=websecure",
          "traefik.http.routers.linkwarden.tls=true",
          "traefik.http.routers.linkwarden.tls.certresolver=letsencrypt",
        ]
        check {
          type     = "http"
          path     = "/"
          interval = "30s"
          timeout  = "10s"
        }
      }
    }
  }
}
