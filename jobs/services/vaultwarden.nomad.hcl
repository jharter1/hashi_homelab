job "vaultwarden" {
  datacenters = ["dc1"]
  type        = "service"

  group "vaultwarden" {
    count = 1

    network {
      mode = "host"
      port "http" {
        static = 8222
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
        DOMAIN = "https://vaultwarden.lab.hartr.net"
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

