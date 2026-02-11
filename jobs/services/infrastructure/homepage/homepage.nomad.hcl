job "homepage" {
  datacenters = ["dc1"]
  type        = "service"

  group "homepage" {
    count = 1

    network {
      mode = "host"
      port "http" {
        static = 3333
      }
    }

    restart {
      attempts = 3
      delay    = "30s"
      interval = "5m"
      mode     = "fail"
    }

    update {
      max_parallel      = 1
      health_check      = "checks"
      min_healthy_time  = "5s"
      healthy_deadline  = "30s"
      progress_deadline = "1m"
      auto_revert       = true
    }

    # Host volume for homepage configuration files
    volume "homepage_config" {
      type      = "host"
      read_only = false
      source    = "homepage_config"
    }

    task "homepage" {
      driver = "docker"

      # Mount config volume
      volume_mount {
        volume      = "homepage_config"
        destination = "/app/config"
        read_only   = false
      }

      env {
        HOMEPAGE_VAR_TITLE     = "Homelab Dashboard"
        LOG_LEVEL              = "info"
        HOSTNAME               = "0.0.0.0"
        PORT                   = "3333"
        HOMEPAGE_ALLOWED_HOSTS = "home.lab.hartr.net"
        NODE_OPTIONS           = "--dns-result-order=ipv4first"
      }

      config {
        image        = "gethomepage/homepage:latest"
        network_mode = "host"
      }

      resources {
        cpu    = 200
        memory = 256
      }

      service {
        name = "homepage"
        port = "http"

        tags = [
          "traefik.enable=true",
          "traefik.http.routers.homepage.rule=Host(`home.lab.hartr.net`)",
          "traefik.http.routers.homepage.entrypoints=websecure",
          "traefik.http.routers.homepage.tls=true",
          "traefik.http.routers.homepage.tls.certresolver=letsencrypt",
        ]

        check {
          type     = "http"
          path     = "/"
          interval = "5s"
          timeout  = "2s"
        }
      }
    }
  }
}
