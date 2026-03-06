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
      port "db" {
        static = 5436
      }
    }

    volume "grafana_data" {
      type      = "host"
      read_only = false
      source    = "grafana_data"
    }

    volume "grafana_postgres_data" {
      type      = "host"
      read_only = false
      source    = "grafana_postgres_data"
    }

    # PostgreSQL database
    task "postgres" {
      driver = "docker"

      # Ensure postgres is ready before grafana starts
      lifecycle {
        hook    = "prestart"
        sidecar = true
      }

      vault {}

      config {
        image        = "postgres:16-alpine"
        network_mode = "host"
        ports        = ["db"]
        privileged   = true
        command      = "postgres"
        args         = ["-p", "5436"]
      }

      volume_mount {
        volume      = "grafana_postgres_data"
        destination = "/var/lib/postgresql/data"
      }

      template {
        destination = "secrets/postgres.env"
        env         = true
        data        = <<EOH
POSTGRES_DB=grafana
POSTGRES_USER=grafana
POSTGRES_PASSWORD={{ with secret "secret/data/postgres/grafana" }}{{ .Data.data.password }}{{ end }}
EOH
      }

      env {
        PGDATA = "/var/lib/postgresql/data/pgdata"
        POSTGRES_HOST_AUTH_METHOD = "scram-sha-256"
        POSTGRES_PORT = "5436"
      }

      resources {
        cpu    = 500
        memory = 256
      }

      service {
        name = "grafana-postgres"
        port = "db"
        tags = ["database", "postgres"]
        
        check {
          type     = "tcp"
          interval = "10s"
          timeout  = "2s"
        }
      }
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

        volumes = [
          # Datasources from centralized config
          "/mnt/nas/configs/observability/grafana/datasources.yml:/etc/grafana/provisioning/datasources/datasources.yml:ro",
          # Dashboard provisioning from centralized config
          "/mnt/nas/configs/observability/grafana/dashboards.yml:/etc/grafana/provisioning/dashboards/dashboards.yml:ro",
        ]
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
GF_DATABASE_HOST=localhost:5436
EOH
      }

      # NOTE: Datasources config now loaded from /mnt/nas/configs/observability/grafana/datasources.yml
      # This eliminates the HEREDOC pattern and centralizes configuration

      env {
        # PostgreSQL database configuration
        # GF_DATABASE_HOST and PASSWORD come from template above
        GF_DATABASE_TYPE = "postgres"
        GF_DATABASE_NAME = "grafana"
        GF_DATABASE_USER = "grafana"
        GF_DATABASE_SSL_MODE = "disable"
        # Increase connection pool and timeout for proxy auth queries
        GF_DATABASE_MAX_OPEN_CONN = "20"
        GF_DATABASE_MAX_IDLE_CONN = "10"
        GF_DATABASE_CONN_MAX_LIFETIME = "14400"
        GF_DATABASE_QUERY_RETRIES = "3"
        
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
        
        # Authelia SSO Integration via Proxy Authentication
        # TEMPORARILY DISABLED - Testing if proxy auth is causing infinite reload
        # GF_AUTH_PROXY_ENABLED = "true"
        # GF_AUTH_PROXY_HEADER_NAME = "Remote-User"
        # GF_AUTH_PROXY_HEADER_PROPERTY = "username"
        # GF_AUTH_PROXY_AUTO_SIGN_UP = "true"
        # GF_AUTH_PROXY_SYNC_TTL = "60"
        # GF_AUTH_PROXY_WHITELIST = "10.0.0.0/24"
        # GF_AUTH_PROXY_HEADERS = "Email:Remote-Email Name:Remote-Name"
        # GF_AUTH_PROXY_ENABLE_LOGIN_TOKEN = "false"
        
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
          # Authelia SSO Protection - TEMPORARILY DISABLED for testing
          # "traefik.http.routers.grafana.middlewares=authelia@file",
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
