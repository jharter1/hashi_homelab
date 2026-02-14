job "woodpecker" {
  datacenters = ["dc1"]
  type        = "service"

  group "woodpecker" {
    count = 1

    network {
      mode = "host"
      port "http" {
        static = 8084
      }
      port "grpc" {
        static = 9000
      }
    }

    volume "woodpecker_data" {
      type      = "host"
      read_only = false
      source    = "woodpecker_data"
    }

    # Woodpecker Server
    task "server" {
      driver = "docker"

      vault {}

      config {
        image        = "woodpeckerci/woodpecker-server:latest"
        network_mode = "host"
        ports        = ["http", "grpc"]
      }

      volume_mount {
        volume      = "woodpecker_data"
        destination = "/var/lib/woodpecker"
      }

      # Vault template for secrets
      template {
        destination = "secrets/woodpecker.env"
        env         = true
        data        = <<EOH
# Agent secret for server-agent communication
WOODPECKER_AGENT_SECRET={{ with secret "secret/data/woodpecker/agent" }}{{ .Data.data.secret }}{{ end }}

# Gitea OAuth credentials
WOODPECKER_GITEA_CLIENT={{ with secret "secret/data/woodpecker/gitea" }}{{ .Data.data.client_id }}{{ end }}
WOODPECKER_GITEA_SECRET={{ with secret "secret/data/woodpecker/gitea" }}{{ .Data.data.client_secret }}{{ end }}
EOH
      }

      env {
        # Server configuration
        WOODPECKER_HOST = "https://ci.lab.hartr.net"
        WOODPECKER_SERVER_ADDR = ":8084"
        WOODPECKER_GRPC_ADDR = ":9000"

        # Gitea integration
        WOODPECKER_GITEA = "true"
        WOODPECKER_GITEA_URL = "https://gitea.lab.hartr.net"

        # Admin user (Gitea username)
        WOODPECKER_ADMIN = "admin"

        # Open registration
        WOODPECKER_OPEN = "true"

        # Database (SQLite for simplicity)
        WOODPECKER_DATABASE_DRIVER = "sqlite3"
        WOODPECKER_DATABASE_DATASOURCE = "/var/lib/woodpecker/woodpecker.sqlite"

        # Log level
        WOODPECKER_LOG_LEVEL = "info"
      }

      resources {
        cpu    = 500
        memory = 512
      }

      service {
        name = "woodpecker-server"
        port = "http"
        tags = [
          "ci-cd",
          "automation",
          "traefik.enable=true",
          "traefik.http.routers.woodpecker.rule=Host(`ci.lab.hartr.net`)",
          "traefik.http.routers.woodpecker.entrypoints=websecure",
          "traefik.http.routers.woodpecker.tls=true",
          "traefik.http.routers.woodpecker.tls.certresolver=letsencrypt",
        ]
        check {
          type     = "http"
          path     = "/healthz"
          interval = "30s"
          timeout  = "5s"
        }
      }
    }

    # Woodpecker Agent
    task "agent" {
      driver = "docker"

      vault {}

      config {
        image        = "woodpeckerci/woodpecker-agent:latest"
        network_mode = "host"
        privileged   = true

        # Mount Docker socket for pipeline execution
        volumes = [
          "/var/run/docker.sock:/var/run/docker.sock"
        ]
      }

      # Vault template for agent secret
      template {
        destination = "secrets/agent.env"
        env         = true
        data        = <<EOH
# Agent secret must match server
WOODPECKER_AGENT_SECRET={{ with secret "secret/data/woodpecker/agent" }}{{ .Data.data.secret }}{{ end }}
EOH
      }

      env {
        # Server connection
        WOODPECKER_SERVER = "localhost:9000"

        # Agent configuration
        WOODPECKER_MAX_WORKFLOWS = "4"
        WOODPECKER_HEALTHCHECK   = "true"

        # Log level
        WOODPECKER_LOG_LEVEL = "info"
      }

      resources {
        cpu    = 1000
        memory = 1024
      }

      service {
        name = "woodpecker-agent"
        tags = [
          "ci-cd-agent",
        ]
        check {
          type     = "tcp"
          port     = "grpc"
          interval = "30s"
          timeout  = "5s"
        }
      }
    }
  }
}
