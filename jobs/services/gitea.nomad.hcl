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

      # Enable Vault workload identity for secrets access
      vault {}

      config {
        image        = "gitea/gitea:latest"
        network_mode = "host"
        ports        = ["http", "ssh"]
      }

      volume_mount {
        volume      = "gitea_data"
        destination = "/data"
      }

      # Vault template for database password
      template {
        destination = "secrets/db.env"
        env         = true
        data        = <<EOH
GITEA__database__PASSWD={{ with secret "secret/data/postgres/gitea" }}{{ .Data.data.password }}{{ end }}
GITEA__database__HOST=postgresql.home:5432
EOH
      }

      env {
        USER_UID = "1000"
        USER_GID = "1000"
        
        # PostgreSQL database configuration
        # GITEA__database__HOST and PASSWD come from template above
        GITEA__database__DB_TYPE = "postgres"
        GITEA__database__NAME = "gitea"
        GITEA__database__USER = "gitea"
        GITEA__database__SSL_MODE = "disable"
        
        # Server configuration
        GITEA__server__DOMAIN = "gitea.home"
        GITEA__server__SSH_DOMAIN = "gitea.home"
        GITEA__server__SSH_PORT = "2222"
        GITEA__server__HTTP_PORT = "3000"
        GITEA__server__ROOT_URL = "http://gitea.home"
        GITEA__server__DISABLE_SSH = "false"
      }

      resources {
        cpu    = 500
        memory = 512
      }

      service {
        name = "gitea-http"
        port = "http"
        tags = [
          "git",
          "development",
          "traefik.enable=true",
          "traefik.http.routers.gitea.rule=Host(`gitea.lab.hartr.net`)",
          "traefik.http.routers.gitea.entrypoints=websecure",
          "traefik.http.routers.gitea.tls=true",
          "traefik.http.routers.gitea.tls.certresolver=letsencrypt",
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

