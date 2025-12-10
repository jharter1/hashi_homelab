job "homepage" {
  datacenters = ["dc1"]
  type        = "service"

  group "homepage" {
    count = 1

    network {
      port "http" {
        static = 8080
      }
    }

    volume "homepage_data" {
      type      = "host"
      read_only = false
      source    = "homepage_data"
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

    task "homepage" {
      driver = "docker"

      vault {
        policies = ["access-secrets"]
      }

      volume_mount {
        volume      = "homepage_data"
        destination = "/app/config"
        read_only   = false
      }

      config {
        image = "gethomepage/homepage:latest"
        ports = ["http"]
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
          "traefik.http.routers.homepage.rule=Host(`home.home`)",
          "traefik.http.routers.homepage.entrypoints=websecure",
          "traefik.http.routers.homepage.tls=true",
        ]

        check {
          type     = "http"
          path     = "/"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}
