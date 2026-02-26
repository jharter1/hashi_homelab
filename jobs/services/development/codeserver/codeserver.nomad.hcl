job "codeserver" {
  datacenters = ["dc1"]
  type        = "service"

  spread {
    attribute = "${node.unique.name}"
  }

  group "codeserver" {
    count = 1

    network {
      port "http" {
        to = 8080 # Container listens on 8080
        # Don't specify static - let Nomad assign a dynamic host port
      }
    }

    volume "codeserver_data" {
      type      = "host"
      read_only = false
      source    = "codeserver_data"
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

      volume_mount {
        volume      = "codeserver_data"
        destination = "/workspace"
        read_only   = false
      }

      config {
        image = "codercom/code-server:latest"
        ports = ["http"]
        args = [
          "--bind-addr", "0.0.0.0:8080",
          "--auth", "none",
          "/workspace"
        ]
      }

      env {
        DOCKER_USER = "1000" # Run as non-root user
      }

      resources {
        cpu        = 500
        memory     = 128
        memory_max = 512
      }

      service {
        name = "codeserver"
        port = "http"

        tags = [
          "traefik.enable=true",
          "traefik.http.routers.codeserver.rule=Host(`code.lab.hartr.net`)",
          "traefik.http.routers.codeserver.entrypoints=websecure",
          "traefik.http.routers.codeserver.tls=true",
          "traefik.http.routers.codeserver.tls.certresolver=letsencrypt",
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