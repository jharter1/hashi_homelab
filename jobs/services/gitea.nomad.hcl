job "gitea" {
  datacenters = ["dc1"]
  type        = "service"

  group "gitea" {
    count = 1

    network {
      mode = "host"
      port "http" {
        static = 3000
      }
      port "ssh" {
        static = 2222
      }
    }

    volume "gitea_data" {
      type      = "host"
      read_only = false
      source    = "gitea_data"
    }

    task "gitea" {
      driver = "docker"

      config {
        image        = "gitea/gitea:latest"
        network_mode = "host"
        ports        = ["http", "ssh"]
      }

      volume_mount {
        volume      = "gitea_data"
        destination = "/data"
      }

      env {
        USER_UID = "1000"
        USER_GID = "1000"
        GITEA__database__DB_TYPE = "sqlite3"
        GITEA__database__PATH = "/data/gitea/gitea.db"
        GITEA__server__DOMAIN = "gitea.home"
        GITEA__server__SSH_DOMAIN = "gitea.home"
        GITEA__server__SSH_PORT = "2222"
        GITEA__server__HTTP_PORT = "3000"
        GITEA__server__ROOT_URL = "http://gitea.home"
        GITEA__server__DISABLE_SSH = "false"
      }

      resources {
        cpu    = 500
        memory = 1024
      }

      service {
        name = "gitea-http"
        port = "http"
        tags = [
          "git",
          "development",
          "traefik.enable=true",
          "traefik.http.routers.gitea.rule=Host(`gitea.home`)",
          "traefik.http.routers.gitea.entrypoints=web",
        ]
        check {
          type     = "http"
          path     = "/api/healthz"
          interval = "10s"
          timeout  = "2s"
        }
      }

      service {
        name = "gitea-ssh"
        port = "ssh"
        tags = ["git", "ssh"]
      }
    }
  }
}

