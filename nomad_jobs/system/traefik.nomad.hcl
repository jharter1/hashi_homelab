job "traefik" {
  datacenters = ["dc1"]
  type        = "system" # Run on every client node

  group "traefik" {
    network {
      port "http" {
        static = 80
      }
      port "admin" {
        static = 8080
      }
    }

    service {
      name = "traefik-dashboard"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.dashboard.rule=Host(`traefik.home`)",
        "traefik.http.routers.dashboard.service=api@internal",
        "traefik.http.routers.dashboard.entrypoints=web",
      ]

      check {
        name     = "alive"
        type     = "tcp"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "traefik" {
      driver = "docker"

      config {
        image        = "traefik:v2.10"
        network_mode = "host" # Important for binding to host ports 80/443

        args = [
          "--api.insecure=true", # Enable Dashboard on 8080
          "--providers.consulcatalog=true",
          "--providers.consulcatalog.exposedByDefault=false",
          "--providers.consulcatalog.endpoint.address=127.0.0.1:8500",
          "--entrypoints.web.address=:80",
        ]
      }
    }
  }
}
