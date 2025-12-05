job "prometheus" {
  datacenters = ["dc1"]
  type        = "service"
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
          "--web.enable-lifecycle",
          "--web.listen-address=:9090",
        ]

        volumes = [
          "local/prometheus.yml:/etc/prometheus/prometheus.yml",
        ]
      }

      volume_mount {
        volume      = "prometheus_data"
        destination = "/prometheus"
      }

      template {
        destination = "local/prometheus.yml"
        data = <<EOH
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['127.0.0.1:9090']

  - job_name: 'node-exporter'
    consul_sd_configs:
      - server: "127.0.0.1:8500"
        services: ["node-exporter"]
    relabel_configs:
      - source_labels: ["__meta_consul_service_address", "__meta_consul_service_port"]
        regex: "(.+);(.*)"
        replacement: "$1:$2"
        target_label: "__address__"
EOH
      }

      resources {
        cpu    = 500
        memory = 512
      }

      service {
        name = "prometheus"
        port = "http"
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
        ]
      }
    }
  }
}