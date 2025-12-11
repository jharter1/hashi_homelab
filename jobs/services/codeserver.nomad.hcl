job "codeserver" {
  datacenters = ["dc1"]
  type        = "service"

  group "codeserver" {
    count = 1

    network {
      port "http" {
        to = 8080 # Container listens on 8080
        # Don't specify static - let Nomad assign a dynamic host port
      }
    }

    volume "homepage_data" {
      type      = "host"
      read_only = false
      source    = "homepage_data"
    }

    # Add other volumes you want to edit
    volume "grafana_data" {
      type      = "host"
      read_only = false
      source    = "grafana_data"
    }

    volume "loki_data" {
      type      = "host"
      read_only = false
      source    = "loki_data"
    }

    restart {
      attempts = 3
      delay    = "30s"
      interval = "5m"
      mode     = "fail"
    }

    update {
      max_parallel     = 1
      health_check     = "checks"
      min_healthy_time = "10s"
      healthy_deadline = "5m"
      auto_revert      = true
    }

    task "codeserver" {
      driver = "docker"

      vault {
        policies = ["access-secrets"]
      }

      # Mount all the config volumes
      volume_mount {
        volume      = "homepage_data"
        destination = "/workspace/homepage"
        read_only   = false
      }

      volume_mount {
        volume      = "grafana_data"
        destination = "/workspace/grafana"
        read_only   = false
      }

      volume_mount {
        volume      = "loki_data"
        destination = "/workspace/loki"
        read_only   = false
      }

      template {
        data        = <<EOT
{{ with secret "secret/data/nomad/codeserver" }}
PASSWORD="{{ .Data.data.password }}"
{{ end }}
EOT
        destination = "secrets/file.env"
        env         = true
      }

      config {
        image = "codercom/code-server:latest"
        ports = ["http"]
        args = [
          "--bind-addr", "0.0.0.0:8080",
          "/workspace"
        ]
      }

      env {
        DOCKER_USER = "1000" # Run as non-root user
      }

      resources {
        cpu    = 500
        memory = 512
      }

      service {
        name = "codeserver"
        port = "http"

        tags = [
          "traefik.enable=true",
          "traefik.http.routers.codeserver.rule=Host(`code.home`)",
          "traefik.http.routers.codeserver.entrypoints=websecure",
          "traefik.http.routers.codeserver.tls=true",
        ]

        check {
          type     = "http"
          path     = "/healthz"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}