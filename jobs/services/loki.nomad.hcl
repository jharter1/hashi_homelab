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
      }

      volume_mount {
        volume      = "loki_data"
        destination = "/loki"
      }

      template {
        destination = "local/local-config.yaml"
        data        = <<EOH
auth_enabled: false

server:
  http_listen_port: 3100
  grpc_listen_port: 9096

common:
  path_prefix: /loki
  storage:
    filesystem:
      chunks_directory: /loki/chunks
      rules_directory: /loki/rules
  replication_factor: 1
  ring:
    instance_addr: 127.0.0.1
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2020-10-24
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h

ruler:
  alertmanager_url: http://localhost:9093

limits_config:
  reject_old_samples: true
  reject_old_samples_max_age: 168h
  ingestion_rate_mb: 10
  ingestion_burst_size_mb: 20
EOH
      }

      resources {
        cpu    = 500
        memory = 512
      }

      service {
        name = "loki"
        port = "http"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.loki.rule=Host(`loki.home`)",
          "traefik.http.routers.loki.entrypoints=websecure",
          "traefik.http.routers.loki.tls=true",
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
