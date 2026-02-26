job "alertmanager" {
  datacenters = ["dc1"]
  type        = "service"

  spread {
    attribute = "${node.unique.name}"
  }

  priority    = 70

  group "alertmanager" {
    count = 1

    network {
      mode = "host"
      port "http" {
        static = 9093
      }
    }

    volume "alertmanager_data" {
      type      = "host"
      read_only = false
      source    = "alertmanager_data"
    }

    task "alertmanager" {
      driver = "docker"

      config {
        image        = "prom/alertmanager:latest"
        network_mode = "host"
        ports        = ["http"]

        args = [
          "--config.file=/etc/alertmanager/alertmanager.yml",
          "--storage.path=/alertmanager",
          "--web.listen-address=:9093",
        ]

        volumes = [
          # Config from centralized location
          "/mnt/nas/configs/observability/alertmanager/alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro",
        ]
      }

      volume_mount {
        volume      = "alertmanager_data"
        destination = "/alertmanager"
      }

      # NOTE: Config now loaded from /mnt/nas/configs/observability/alertmanager/alertmanager.yml
      # This eliminates the HEREDOC pattern and centralizes configuration

      resources {
        cpu        = 100
        memory     = 64
        memory_max = 128
      }

      service {
        name         = "alertmanager"
        port         = "http"
        address_mode = "host"

        check {
          type     = "http"
          path     = "/-/healthy"
          interval = "10s"
          timeout  = "2s"
          port     = "http"
        }

        tags = [
          "monitoring",
          "alertmanager",
          "traefik.enable=true",
          "traefik.http.routers.alertmanager.rule=Host(`alertmanager.lab.hartr.net`)",
          "traefik.http.routers.alertmanager.entrypoints=websecure",
          "traefik.http.routers.alertmanager.tls=true",
          "traefik.http.routers.alertmanager.tls.certresolver=letsencrypt",
          "traefik.http.routers.alertmanager.middlewares=authelia@file",
        ]
      }
    }
  }
}

