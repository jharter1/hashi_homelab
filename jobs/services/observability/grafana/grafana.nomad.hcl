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

      # Enable Vault workload identity for secrets access
      vault {}

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

      # Vault template for database password
      template {
        destination = "secrets/db.env"
        env         = true
        data        = <<EOH
GF_DATABASE_PASSWORD={{ with secret "secret/data/postgres/grafana" }}{{ .Data.data.password }}{{ end }}
GF_DATABASE_HOST=postgresql.home:5432
EOH
      }

      # Provision Prometheus datasource
      template {
        destination = "local/provisioning/datasources/prometheus.yml"
        data        = <<EOH
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus.service.consul:9090
    isDefault: true
    editable: true
    jsonData:
      timeInterval: 15s
EOH
      }

      env {
        # Provisioning paths
        GF_PATHS_PROVISIONING = "/local/provisioning"
        # PostgreSQL database configuration
        # GF_DATABASE_HOST and PASSWORD come from template above
        GF_DATABASE_TYPE = "postgres"
        GF_DATABASE_NAME = "grafana"
        GF_DATABASE_USER = "grafana"
        GF_DATABASE_SSL_MODE = "disable"
        
        # Security
        GF_SECURITY_ADMIN_PASSWORD = "admin"
        GF_SERVER_HTTP_PORT = "3000"
        
        # Server configuration
        GF_AUTH_ANONYMOUS_ENABLED = "false"
        GF_SERVER_ROOT_URL = "https://grafana.lab.hartr.net"
        GF_SERVER_SERVE_FROM_SUB_PATH = "false"
        GF_SERVER_ENFORCE_DOMAIN = "false"
        GF_SERVER_PROTOCOL = "http"
        GF_SERVER_ENABLE_GZIP = "true"
        
        # Fix Monaco Editor loading issues
        GF_SECURITY_CONTENT_SECURITY_POLICY = "false"
        GF_SECURITY_STRICT_TRANSPORT_SECURITY = "false"
      }

      resources {
        cpu    = 500
        memory = 512
      }

      service {
        name = "grafana"
        port = "http"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.grafana.rule=Host(`grafana.lab.hartr.net`)",
          "traefik.http.routers.grafana.entrypoints=websecure",
          "traefik.http.routers.grafana.tls=true",
          "traefik.http.routers.grafana.tls.certresolver=letsencrypt",
          # Authelia SSO Protection
          "traefik.http.routers.grafana.middlewares=authelia@file",
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
