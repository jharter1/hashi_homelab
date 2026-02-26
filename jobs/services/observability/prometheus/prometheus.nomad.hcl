job "prometheus" {
  datacenters = ["dc1"]
  type        = "service"

  spread {
    attribute = "${node.unique.name}"
  }

  priority    = 60

  group "prometheus" {
    count = 1

    network {
      mode = "host"
      port "http" {
        static = 9090
      }
    }

    volume "prometheus_data" {
      type   = "host"
      source = "prometheus_data"
    }

    task "prometheus" {
      driver = "docker"

      config {
        image        = "prom/prometheus:latest"
        network_mode = "host"
        ports        = ["http"]

        args = [
          "--config.file=/etc/prometheus/prometheus.yml",
          "--storage.tsdb.path=/prometheus",
          "--storage.tsdb.retention.time=30d",
          "--storage.tsdb.no-lockfile",
          "--web.enable-lifecycle",
          "--web.listen-address=:9090",
        ]

        volumes = [
          "/mnt/nas/configs/observability/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro",
          "/mnt/nas/configs/observability/prometheus/rules:/etc/prometheus/rules:ro",
        ]
      }

      env {
        # Dummy env var - queries.active path cannot be overridden
        # Directory permissions set to 777 to allow query log creation
      }

      volume_mount {
        volume      = "prometheus_data"
        destination = "/prometheus"
      }

      # NOTE: Config now loaded from /mnt/nas/configs/observability/prometheus/prometheus.yml
      # This eliminates the HEREDOC pattern and centralizes configuration

      resources {
        cpu        = 300
        memory     = 256
        memory_max = 512
      }

      service {
        name         = "prometheus"
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
          "prometheus",
          "traefik.enable=true",
          "traefik.http.routers.prometheus.rule=Host(`prometheus.lab.hartr.net`)",
          "traefik.http.routers.prometheus.entrypoints=websecure",
          "traefik.http.routers.prometheus.tls=true",
          "traefik.http.routers.prometheus.tls.certresolver=letsencrypt",
          # No Authelia middleware - internal monitoring service
        ]
      }
    }
  }
}