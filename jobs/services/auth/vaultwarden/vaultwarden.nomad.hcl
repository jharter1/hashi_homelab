job "vaultwarden" {
  datacenters = ["dc1"]
  type        = "service"

  spread {
    attribute = "${node.unique.name}"
  }

  group "vaultwarden" {
    count = 1

    network {
      mode = "host"
      port "http" {
        static = 8222
      }
      port "db" {
        static = 5438
      }
    }

    volume "vaultwarden_data" {
      type      = "host"
      read_only = false
      source    = "vaultwarden_data"
    }

    volume "vaultwarden_postgres_data" {
      type      = "host"
      read_only = false
      source    = "vaultwarden_postgres_data"
    }

    # PostgreSQL database
    task "postgres" {
      driver = "docker"

      # Ensure postgres is ready before vaultwarden starts
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
        command      = "postgres"
        args         = ["-p", "5438"]
      }

      volume_mount {
        volume      = "vaultwarden_postgres_data"
        destination = "/var/lib/postgresql/data"
      }

      template {
        destination = "secrets/postgres.env"
        env         = true
        change_mode = "noop"
        data        = <<EOH
POSTGRES_DB=vaultwarden
POSTGRES_USER=vaultwarden
POSTGRES_PASSWORD={{ with secret "secret/data/postgres/vaultwarden" }}{{ .Data.data.password }}{{ end }}
EOH
      }

      env {
        PGDATA = "/var/lib/postgresql/data/pgdata"
        POSTGRES_HOST_AUTH_METHOD = "scram-sha-256"
        POSTGRES_PORT = "5438"
      }

      resources {
        cpu        = 200
        memory     = 32
        memory_max = 128
      }

      service {
        name = "vaultwarden-postgres"
        port = "db"
        tags = ["database", "postgres"]
        
        check {
          type     = "tcp"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }

    task "vaultwarden" {
      driver = "docker"

      # Enable Vault workload identity for secrets access
      vault {}

      config {
        image        = "vaultwarden/server:latest"
        network_mode = "host"
        ports        = ["http"]
      }

      volume_mount {
        volume      = "vaultwarden_data"
        destination = "/data"
      }

      # Vault template for database password
      template {
        destination = "secrets/db.env"
        env         = true
        change_mode = "noop"
        data        = <<EOH
DATABASE_URL=postgresql://vaultwarden:{{ with secret "secret/data/postgres/vaultwarden" }}{{ .Data.data.password }}{{ end }}@localhost:5438/vaultwarden
EOH
      }

      env {
        # DATABASE_URL comes from Vault template above
        
        # Port configuration (vaultwarden defaults to 80, we use 8222)
        ROCKET_PORT = "8222"
        
        # Disable admin token for now (set via web UI or env var)
        # ADMIN_TOKEN = "your-admin-token-here"
        # Enable signups (disable in production)
        SIGNUPS_ALLOWED = "true"
        # Domain configuration
        DOMAIN = "https://vaultwarden.lab.hartr.net"
        # WebSocket support
        WEBSOCKET_ENABLED = "true"
        # Logging
        LOG_LEVEL = "warn"
        # Disable YubiKey/2FA for simplicity (enable if needed)
        DISABLE_YUBICO = "true"
      }

      resources {
        cpu        = 100
        memory     = 32
        memory_max = 128
      }

      service {
        name = "vaultwarden"
        port = "http"
        address_mode = "host"
        tags = [
          "security",
          "password-manager",
          "traefik.enable=true",
          "traefik.http.routers.vaultwarden.rule=Host(`vaultwarden.lab.hartr.net`)",
          "traefik.http.routers.vaultwarden.entrypoints=websecure",
          "traefik.http.routers.vaultwarden.tls=true",
          "traefik.http.routers.vaultwarden.tls.certresolver=letsencrypt",
        ]
        check {
          type     = "http"
          path     = "/alive"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}


