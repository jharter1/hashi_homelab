job "it-tools" {
  datacenters = ["dc1"]
  type        = "service"

  spread {
    attribute = "${node.unique.name}"
  }

  group "it-tools" {
    count = 1

    network {
      port "http" {
        to = 80 # Container listens on 80
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
      healthy_deadline = "3m"
      auto_revert      = true
    }

    task "it-tools" {
      driver = "docker"

      config {
        image = "corentinth/it-tools:latest"
        ports = ["http"]
        privileged = true
      }

      resources {
        cpu        = 100
        memory     = 16
        memory_max = 64
      }

      service {
        name = "it-tools"
        port = "http"

        tags = [
          "traefik.enable=true",
          "traefik.http.routers.it-tools.rule=Host(`tools.lab.hartr.net`)",
          "traefik.http.routers.it-tools.entrypoints=websecure",
          "traefik.http.routers.it-tools.tls=true",
          "traefik.http.routers.it-tools.tls.certresolver=letsencrypt",
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
