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

      # Fetch the Vault CA chain for trusting internal HTTPS services
      # TODO: Enable once PKI intermediate CA is generated
      # artifact {
      #   source      = "http://10.0.0.30:8200/v1/pki_int/ca/pem"
      #   destination = "local/homelab-ca-chain.crt"
      #   mode        = "file"
      # }

      config {
        image        = "grafana/grafana:latest"
        network_mode = "host"
        ports        = ["http"]
        dns_servers  = ["10.0.0.10", "1.1.1.1"]
      }

      volume_mount {
        volume      = "grafana_data"
        destination = "/var/lib/grafana"
      }

      env {
        GF_SECURITY_ADMIN_PASSWORD = "admin"
        GF_SERVER_HTTP_PORT = "3000"
        # Disable anonymous access now that we have secure admin credentials
        GF_AUTH_ANONYMOUS_ENABLED = "false"
        # Configure Grafana to work behind a reverse proxy
        GF_SERVER_ROOT_URL = "http://grafana.home"
        GF_SERVER_SERVE_FROM_SUB_PATH = "false"
        GF_SERVER_ENFORCE_DOMAIN = "false"
        GF_SERVER_PROTOCOL = "http"
        GF_SERVER_ENABLE_GZIP = "true"
      }

      service {
        name = "grafana"
        port = "http"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.grafana.rule=Host(`grafana.home`)",
          "traefik.http.routers.grafana.entrypoints=web",
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
