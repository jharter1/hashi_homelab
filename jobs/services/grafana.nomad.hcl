job "grafana" {
  datacenters = ["dc1"]
  type        = "service"

  group "grafana" {
    count = 1

    network {
      mode = "host"
      port "http" {
        static = 3000
      }
    }

    volume "grafana_data" {
      type      = "host"
      read_only = false
      source    = "grafana_data"
    }

    task "grafana" {
      driver = "docker"

      config {
        image        = "grafana/grafana:latest"
        network_mode = "host"
        ports        = ["http"]
        dns_servers  = ["10.0.0.10", "1.1.1.1"]
      }

      env {
        GF_SERVER_HTTP_PORT = "3000"
        GF_AUTH_ANONYMOUS_ENABLED = "true"
        GF_AUTH_ANONYMOUS_ORG_ROLE = "Admin"
      }

      service {
        name = "grafana"
        port = "http"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.grafana.rule=Host(`grafana.localhost`)",
        ]
        check {
          type     = "http"
          path     = "/api/health"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}
