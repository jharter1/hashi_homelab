job "uptime-kuma" {
  datacenters = ["dc1"]

  group "uptime-kuma-group" {
    count = 1

    network {
      port "http" {
        to = 3001
      }
    }

    service {
      name = "uptime-kuma"
      port = "http"
      
      tags = [
        "traefik.enable=true",
        "traefik.http.routers.uptime-kuma.rule=Host(`uptime-kuma.home`)",
        "traefik.http.routers.uptime-kuma.entrypoints=web",
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
      
      config {
        image = "louislam/uptime-kuma:2.0.2"
        ports = ["http"]
        volumes = [
          "local/uptime-kuma/data:/app/data"
        ]
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