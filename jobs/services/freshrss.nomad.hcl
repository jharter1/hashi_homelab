job "freshrss" {
  datacenters = ["dc1"]
  type        = "service"

  group "freshrss" {
    count = 1

    network {
      mode = "host"
      port "http" {
        static = 8080
      }
    }

    volume "freshrss_data" {
      type      = "host"
      read_only = false
      source    = "freshrss_data"
    }

    task "freshrss" {
      driver = "docker"

      config {
        image        = "freshrss/freshrss:latest"
        network_mode = "host"
        ports        = ["http"]
      }

      volume_mount {
        volume      = "freshrss_data"
        destination = "/var/www/FreshRSS/data"
      }

      # Vault template for database credentials
      template {
        destination = "secrets/db.env"
        env         = true
        data        = <<EOH
# Database configuration
DB_BASE=freshrss
DB_HOST=localhost
DB_PORT=5432
DB_USER=freshrss
DB_PASSWORD={{ with secret "secret/data/postgres/freshrss" }}{{ .Data.data.password }}{{ end }}
EOH
      }

      env {
        # General settings
        CRON_MIN = "*/20"
        TZ       = "America/New_York"
        
        # Database type
        DB_PREFIX = "freshrss_"
        
        # FreshRSS admin credentials (initial setup)
        # After first login, change these via the web UI
        ADMIN_EMAIL    = "admin@home.local"
        ADMIN_PASSWORD = "changeme"
        ADMIN_API_PASSWORD = "changeme_api"
        
        # Application URL
        BASE_URL = "http://freshrss.home"
        
        # Security
        TRUSTED_PROXY = "10.0.0.0/24"
      }

      resources {
        cpu    = 500
        memory = 512
      }

      service {
        name = "freshrss"
        port = "http"
        tags = [
          "rss",
          "feed-reader",
          "traefik.enable=true",
          "traefik.http.routers.freshrss.rule=Host(`freshrss.home`)",
          "traefik.http.routers.freshrss.entrypoints=web",
        ]
        check {
          type     = "http"
          path     = "/i/"
          interval = "30s"
          timeout  = "5s"
        }
      }
    }

    # Cron task for updating feeds
    task "freshrss-cron" {
      driver = "docker"

      lifecycle {
        hook    = "poststart"
        sidecar = true
      }

      config {
        image   = "freshrss/freshrss:latest"
        command = "cron"
        args    = ["-f"]

        volumes = [
          "${NOMAD_ALLOC_DIR}/../freshrss_data:/var/www/FreshRSS/data"
        ]
      }

      template {
        destination = "secrets/db.env"
        env         = true
        data        = <<EOH
DB_BASE=freshrss
DB_HOST=localhost
DB_PORT=5432
DB_USER=freshrss
DB_PASSWORD={{ with secret "secret/data/postgres/freshrss" }}{{ .Data.data.password }}{{ end }}
EOH
      }

      env {
        CRON_MIN = "*/20"
        TZ       = "America/New_York"
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
}
