job "loki" {
  datacenters = ["dc1"]
  type        = "service"

  group "loki" {
    count = 1

    network {
      mode = "host"
      port "http" {
        static = 3100
      }
      port "grpc" {
        static = 9096
      }
    }

    volume "loki_data" {
      type      = "host"
      read_only = false
      source    = "loki_data"
    }

    task "loki" {
      driver = "docker"

      config {
        image        = "grafana/loki:3.6.0"
        network_mode = "host"
        ports        = ["http", "grpc"]

        args = [
          "-config.file=/etc/loki/local-config.yaml",
        ]

        volumes = [
          # Config from centralized location
          "/mnt/nas/configs/observability/loki/loki.yaml:/etc/loki/local-config.yaml:ro",
        ]
      }

      volume_mount {
        volume      = "loki_data"
        destination = "/loki"
      }

      # NOTE: Config now loaded from /mnt/nas/configs/observability/loki/loki.yaml
      # This eliminates the HEREDOC pattern and centralizes configuration

      resources {
        cpu    = 500
        memory = 512
      }

      service {
        name = "loki"
        port = "http"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.loki.rule=Host(`loki.lab.hartr.net`)",
          "traefik.http.routers.loki.entrypoints=websecure",
          "traefik.http.routers.loki.tls=true",
          "traefik.http.routers.loki.tls.certresolver=letsencrypt",
        ]
        check {
          type     = "http"
          path     = "/ready"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}
