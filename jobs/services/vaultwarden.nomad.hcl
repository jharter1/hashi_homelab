job "vaultwarden" {
  datacenters = ["dc1"]
  type        = "service"

  group "vaultwarden" {
    count = 1

    network {
      mode = "host"
      port "http" {
        static = 80
      }
    }

    volume "vaultwarden_data" {
      type      = "host"
      read_only = false
      source    = "vaultwarden_data"
    }

    task "vaultwarden" {
      driver = "docker"

      config {
        image        = "vaultwarden/server:latest"
        network_mode = "host"
        ports        = ["http"]
      }

      volume_mount {
        volume      = "vaultwarden_data"
        destination = "/data"
      }

      env {
        # Use SQLite for simplicity (can be changed to PostgreSQL later)
        DATABASE_URL = "/data/db.sqlite3"
        # Disable admin token for now (set via web UI or env var)
        # ADMIN_TOKEN = "your-admin-token-here"
        # Enable signups (disable in production)
        SIGNUPS_ALLOWED = "true"
        # Domain configuration
        DOMAIN = "http://vaultwarden.home"
        # WebSocket support
        WEBSOCKET_ENABLED = "true"
        # Logging
        LOG_LEVEL = "warn"
        # Disable YubiKey/2FA for simplicity (enable if needed)
        DISABLE_YUBICO = "true"
      }

      resources {
        cpu    = 500
        memory = 512
      }

      service {
        name = "vaultwarden"
        port = "http"
        tags = [
          "security",
          "password-manager",
          "traefik.enable=true",
          "traefik.http.routers.vaultwarden.rule=Host(`vaultwarden.home`)",
          "traefik.http.routers.vaultwarden.entrypoints=websecure",
          "traefik.http.routers.vaultwarden.tls=true",
          # Note: HTTPS certificate configuration needed (see plan for Vault PKI setup)
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

