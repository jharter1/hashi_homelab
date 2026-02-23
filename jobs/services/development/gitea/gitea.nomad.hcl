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
        image        = "gitea/gitea:latest-rootless"
        network_mode = "host"
        ports        = ["http"]
      }
      
      # Run as user 1000 to match NFS ownership
      user = "1000:1000"

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
GITEA__database__HOST={{ range service "postgresql" }}{{ .Address }}{{ end }}:5432
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
        
        # Server configuration - HTTPS only, no SSH
        GITEA__server__DOMAIN = "gitea.lab.hartr.net"
        GITEA__server__HTTP_PORT = "3000"
        GITEA__server__ROOT_URL = "https://gitea.lab.hartr.net"
        GITEA__server__DISABLE_SSH = "true"
        GITEA__server__START_SSH_SERVER = "false"
        GITEA__server__OFFLINE_MODE = "false"
        
        # Trust Authelia's forwarded authentication headers (optional - not required for login)
        GITEA__service__ENABLE_REVERSE_PROXY_AUTHENTICATION = "false"
        GITEA__service__ENABLE_REVERSE_PROXY_AUTO_REGISTRATION = "false"
      }

      resources {
        cpu    = 500
        memory = 512
      }

      service {
        name         = "gitea-http"
        port         = "http"
        address_mode = "driver"
        tags = [
          "git",
          "development",
          "traefik.enable=true",
          "traefik.http.routers.gitea.rule=Host(`gitea.lab.hartr.net`)",
          "traefik.http.routers.gitea.entrypoints=websecure",
          "traefik.http.routers.gitea.tls=true",
          "traefik.http.routers.gitea.tls.certresolver=letsencrypt",
          "traefik.http.routers.gitea.middlewares=authelia@file",
        ]
        check {
          type     = "tcp"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}


