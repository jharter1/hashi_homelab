job "harbor" {
  datacenters = ["dc1"]
  type        = "service"

  group "harbor" {
    count = 1

    network {
      mode = "host"
      port "http" {
        static = 5000
      }
      port "db" {
        static = 5436
      }
      port "redis" {
        static = 6381
      }
    }

    volume "harbor_data" {
      type      = "host"
      read_only = false
      source    = "harbor_data"
    }

    volume "harbor_registry" {
      type      = "host"
      read_only = false
      source    = "harbor_registry"
    }

    volume "harbor_redis" {
      type      = "host"
      read_only = false
      source    = "harbor_redis"
    }

    volume "harbor_postgres_data" {
      type      = "host"
      read_only = false
      source    = "harbor_postgres_data"
    }

    # PostgreSQL database
    task "postgres" {
      driver = "docker"

      vault {}

      config {
        image        = "postgres:16-alpine"
        network_mode = "host"
        ports        = ["db"]
      }

      volume_mount {
        volume      = "harbor_postgres_data"
        destination = "/var/lib/postgresql/data"
      }

      template {
        destination = "secrets/postgres.env"
        env         = true
        data        = <<EOH
POSTGRES_DB=harbor
POSTGRES_USER=harbor
POSTGRES_PASSWORD={{ with secret "secret/data/postgres/harbor" }}{{ .Data.data.password }}{{ end }}
EOH
      }

      env {
        PGDATA = "/var/lib/postgresql/data/pgdata"
      }

      resources {
        cpu    = 500
        memory = 512
      }

      service {
        name = "harbor-postgres"
        port = "db"
        tags = ["database", "postgres"]
        
        check {
          type     = "tcp"
          interval = "30s"
          timeout  = "5s"
        }
      }
    }

    # Redis for Harbor caching
    task "redis" {
      driver = "docker"

      config {
        image        = "redis:7-alpine"
        network_mode = "host"
        ports        = ["redis"]
        args         = ["redis-server", "--port", "6381"]
      }

      volume_mount {
        volume      = "harbor_redis"
        destination = "/data"
      }

      resources {
        cpu    = 200
        memory = 128
      }

      service {
        name = "harbor-redis"
        port = "redis"
        check {
          type     = "tcp"
          interval = "30s"
          timeout  = "5s"
        }
      }
    }

    # Harbor core service
    task "harbor" {
      driver = "docker"

      vault {}

      config {
        image        = "goharbor/harbor-core:v2.11.0"
        network_mode = "host"
        ports        = ["http"]
      }

      volume_mount {
        volume      = "harbor_data"
        destination = "/data"
      }

      volume_mount {
        volume      = "harbor_registry"
        destination = "/storage"
      }

      # Vault template for database credentials
      template {
        destination = "secrets/harbor.env"
        env         = true
        data        = <<EOH
# Database configuration
POSTGRESQL_HOST=localhost
POSTGRESQL_PORT=5436
POSTGRESQL_DATABASE=harbor
POSTGRESQL_USERNAME=harbor
POSTGRESQL_PASSWORD={{ with secret "secret/data/postgres/harbor" }}{{ .Data.data.password }}{{ end }}

# Harbor admin password
HARBOR_ADMIN_PASSWORD={{ with secret "secret/data/harbor/admin" }}{{ .Data.data.password }}{{ end }}
EOH
      }

      env {
        # Core configuration
        CORE_URL = "http://localhost:5000"
        JOBSERVICE_URL = "http://localhost:5000"
        REGISTRY_URL = "http://localhost:5001"
        TOKEN_SERVICE_URL = "http://localhost:5000/service/token"
        
        # External URL
        EXT_ENDPOINT = "https://harbor.lab.hartr.net"
        
        # Redis configuration
        REDIS_HOST = "localhost:6381"
        
        # Registry storage
        REGISTRY_STORAGE_PROVIDER_NAME = "filesystem"
        REGISTRY_STORAGE_PROVIDER_CONFIG = '{"rootdirectory":"/storage"}'
        
        # Security
        CSRF_KEY = "must-be-a-secret-string-of-length-32"
        
        # Logging
        LOG_LEVEL = "info"
        
        # Registration
        AUTH_MODE = "db_auth"
        SELF_REGISTRATION = "on"
        
        # Trivy (vulnerability scanner) - disabled for now
        SCANNER_SKIP_UPDATE = "true"
      }

      resources {
        cpu    = 1000
        memory = 1024
      }

      service {
        name = "harbor"
        port = "http"
        tags = [
          "container-registry",
          "harbor",
          "traefik.enable=true",
          "traefik.http.routers.harbor.rule=Host(`harbor.lab.hartr.net`)",
          "traefik.http.routers.harbor.entrypoints=websecure",
          "traefik.http.routers.harbor.tls=true",
          "traefik.http.routers.harbor.tls.certresolver=letsencrypt",
        ]
        check {
          type     = "http"
          path     = "/api/v2.0/health"
          interval = "30s"
          timeout  = "5s"
        }
      }
    }
  }
}
