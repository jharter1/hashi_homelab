job "speedtest" {
  datacenters = ["dc1"]
  type        = "service"

  group "speedtest" {
    count = 1

    network {
      port "http" {
        static = 8765
        to     = 80
      }
    }

    volume "speedtest_data" {
      type      = "host"
      read_only = false
      source    = "speedtest_data"
    }

    task "speedtest" {
      driver = "docker"

      # Enable Vault workload identity for secrets access
      vault {}

      config {
        image        = "lscr.io/linuxserver/speedtest-tracker:latest"
        ports        = ["http"]
        privileged   = true
      }

      volume_mount {
        volume      = "speedtest_data"
        destination = "/config"
      }

      # Vault template for database password
      template {
        destination = "secrets/db.env"
        env         = true
        data        = <<EOH
DB_PASSWORD={{ with secret "secret/data/postgres/speedtest" }}{{ .Data.data.password }}{{ end }}
DB_HOST={{ range service "postgresql" }}{{ .Address }}{{ end }}
EOH
      }

      env {
        PUID = "1000"
        PGID = "1000"
        APP_KEY = "base64:4cVfJ7AmsGsW1DLHcn4VzvfA3bq6kOglrkTgVIZTKWU="
        APP_TIMEZONE = "America/Chicago"
        APP_URL = "https://speedtest.lab.hartr.net"
        # PostgreSQL configuration (DB_HOST and DB_PASSWORD from Vault template above)
        DB_CONNECTION = "pgsql"
        DB_PORT = "5432"
        DB_DATABASE = "speedtest"
        DB_USERNAME = "speedtest"
        SPEEDTEST_SCHEDULE = "0 */6 * * *"  # Every 6 hours
        SPEEDTEST_SERVERS = ""
        PRUNE_RESULTS_OLDER_THAN = "365"  # Keep results for 1 year
        CHART_DATETIME_FORMAT = "M/d H:i"
        DATETIME_FORMAT = "m/d/Y H:i:s"
        SKIP_CHECK_WEB_SERVER = "true"
      }

      resources {
        cpu    = 1000
        memory = 1024
      }

      service {
        name = "speedtest"
        port = "http"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.speedtest.rule=Host(`speedtest.lab.hartr.net`)",
          "traefik.http.routers.speedtest.entrypoints=websecure",
          "traefik.http.routers.speedtest.tls=true",
          "traefik.http.routers.speedtest.tls.certresolver=letsencrypt",
          "traefik.http.routers.speedtest.middlewares=authelia@file",
        ]
        check {
          type     = "http"
          path     = "/"
          interval = "30s"
          timeout  = "5s"
          check_restart {
            limit = 3
            grace = "30s"
          }
        }
      }
    }
  }
}
