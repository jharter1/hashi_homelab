job "uptime-kuma" {
  datacenters = ["dc1"]

  group "uptime-kuma-group" {
    count = 1

    network {
      port "http" {
        to = 3001
      }
    }

    volume "uptime_kuma_data" {
      type      = "host"
      read_only = false
      source    = "uptime_kuma_data"
    }

    service {
      name = "uptime-kuma"
      port = "http"
      
      tags = [
        "traefik.enable=true",
        # Main UI router - protected by Authelia
        "traefik.http.routers.uptime-kuma.rule=Host(`uptime-kuma.lab.hartr.net`)",
        "traefik.http.routers.uptime-kuma.entrypoints=websecure",
        "traefik.http.routers.uptime-kuma.tls=true",
        "traefik.http.routers.uptime-kuma.tls.certresolver=letsencrypt",
        "traefik.http.routers.uptime-kuma.middlewares=authelia@file",
        "traefik.http.routers.uptime-kuma.priority=1",
        # API router - bypasses Authelia for status page API (used by Homepage widget)
        "traefik.http.routers.uptime-kuma-api.rule=Host(`uptime-kuma.lab.hartr.net`) && PathPrefix(`/api/status-page`)",
        "traefik.http.routers.uptime-kuma-api.entrypoints=websecure",
        "traefik.http.routers.uptime-kuma-api.tls=true",
        "traefik.http.routers.uptime-kuma-api.tls.certresolver=letsencrypt",
        "traefik.http.routers.uptime-kuma-api.priority=10",
      ]

      check {
        name     = "uptime-kuma-health"
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "uptime-kuma" {
      driver = "docker"
      
      # Enable Vault workload identity for secrets access
      vault {}
      
      volume_mount {
        volume      = "uptime_kuma_data"
        destination = "/app/data"
        read_only   = false
      }
      
      # Vault template for database connection string
      template {
        destination = "secrets/db.env"
        env         = true
        data        = <<EOH
UPTIME_KUMA_DB_CONNECTION_STRING=postgres://uptimekuma:{{ with secret "secret/data/postgres/uptimekuma" }}{{ .Data.data.password }}{{ end }}@{{ range service "postgresql" }}{{ .Address }}{{ end }}:5432/uptimekuma
EOH
      }
      
      env {
        UPTIME_KUMA_DISABLE_FRAME_SAMEORIGIN = "true"
        DATA_DIR = "/app/data"
        # UPTIME_KUMA_DB_CONNECTION_STRING comes from Vault template above
      }
      
      config {
        image = "louislam/uptime-kuma:2.0.2"
        ports = ["http"]
      }

      restart {
        attempts = 3
        interval = "5m"
        delay    = "25s"
        mode     = "fail"
      }

      resources {
        cpu    = 500
        memory = 512
      }
    }
  }
}