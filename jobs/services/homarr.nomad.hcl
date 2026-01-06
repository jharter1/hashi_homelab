job "homarr" {
  datacenters = ["dc1"]
  type        = "service"

  group "homarr" {
    count = 1

    network {
      mode = "host"
      port "http" {
        static = 7575
      }
    }

    restart {
      attempts = 3
      delay    = "30s"
      interval = "5m"
      mode     = "fail"
    }

    update {
      max_parallel     = 1
      health_check     = "checks"
      min_healthy_time = "10s"
      healthy_deadline = "5m"
      auto_revert      = true
    }

    task "homarr" {
      driver = "docker"

      # Let Homarr create its own default config
      # You can configure it through the web UI

      # Let Homarr create its own default config
      # You can configure it through the web UI

      # Homarr stores data in local volumes
      config {
        image = "ghcr.io/ajnart/homarr:latest"
        network_mode = "host"
        
        # Use local storage for configs and data
        volumes = [
          "local/homarr/configs:/app/data/configs",
          "local/homarr/icons:/app/public/icons",
          "local/homarr/data:/data",
        ]
      }

      env {
        # Set timezone
        TZ = "America/Chicago"
        
        # Homarr configuration
        BASE_URL = "http://homarr.home"
        PORT = "7575"
        HOSTNAME = "0.0.0.0"
        
        # Disable authentication for local network
        DISABLE_AUTH = "true"
        
        # Enable analytics (optional)
        # ANALYTICS_ENABLED = "false"
      }

      resources {
        cpu    = 200
        memory = 256
      }

      service {
        name = "homarr"
        port = "http"

        tags = [
          "traefik.enable=true",
          "traefik.http.routers.homarr.rule=Host(`homarr.home`)",
          "traefik.http.routers.homarr.entrypoints=web",
        ]

        check {
          type     = "tcp"
          port     = "http"
          interval = "30s"
          timeout  = "10s"
          
          check_restart {
            limit = 2
            grace = "60s"
            ignore_warnings = false
          }
        }
      }
    }
  }
}
