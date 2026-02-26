job "tempo" {
  datacenters = ["dc1"]
  type        = "service"

  spread {
    attribute = "${node.unique.name}"
  }

  group "tempo" {
    count = 1

    network {
      mode = "host"
      port "http" {
        static = 3200
      }
      port "otlp_grpc" {
        static = 4317
      }
      port "otlp_http" {
        static = 4318
      }
    }

    volume "tempo_data" {
      type      = "host"
      read_only = false
      source    = "tempo_data"
    }

    task "tempo" {
      driver = "docker"

      config {
        image        = "grafana/tempo:latest"
        network_mode = "host"
        ports        = ["http", "otlp_grpc", "otlp_http"]

        args = [
          "-config.file=/etc/tempo/tempo.yaml",
        ]

        volumes = [
          "/mnt/nas/configs/observability/tempo/tempo.yaml:/etc/tempo/tempo.yaml:ro",
        ]
      }

      volume_mount {
        volume      = "tempo_data"
        destination = "/var/tempo"
      }

      resources {
        cpu        = 200
        memory     = 256
        memory_max = 512
      }

      service {
        name = "tempo"
        port = "http"
        tags = ["tracing", "observability"]
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
