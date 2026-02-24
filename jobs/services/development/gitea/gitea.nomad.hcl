job "gitea" {
  datacenters = ["dc1"]
  type        = "service"

  group "gitea" {
    count = 1

    network {
      mode = "host"
      port "http" {
        static = 3001
      }
      port "db" {
        static = 5437
      }
    }

    volume "gitea_data" {
      type      = "host"
      read_only = false
      source    = "gitea_data"
    }

    volume "gitea_postgres_data" {
      type      = "host"
      read_only = false
      source    = "gitea_postgres_data"
    }

    # PostgreSQL database
    task "postgres" {
      driver = "docker"

      # Ensure postgres is ready before gitea starts
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
        args         = ["-p", "5437"]
      }

      volume_mount {
        volume      = "gitea_postgres_data"
        destination = "/var/lib/postgresql/data"
      }

      template {
        destination = "secrets/postgres.env"
        env         = true
        data        = <<EOH
POSTGRES_DB=gitea
POSTGRES_USER=gitea
POSTGRES_PASSWORD={{ with secret "secret/data/postgres/gitea" }}{{ .Data.data.password }}{{ end }}
EOH
      }

      env {
        PGDATA = "/var/lib/postgresql/data/pgdata"
        POSTGRES_HOST_AUTH_METHOD = "scram-sha-256"
        POSTGRES_PORT = "5437"
      }

      resources {
        cpu    = 500
        memory = 256
      }

      service {
        name = "gitea-postgres"
        port = "db"
        tags = ["database", "postgres"]
        
        check {
          type     = "tcp"
          interval = "10s"
          timeout  = "2s"
        }
      }
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
EOH
      }

      env {
        USER_UID = "1000"
        USER_GID = "1000"
        
        # PostgreSQL database configuration
        GITEA__database__DB_TYPE = "postgres"
        GITEA__database__HOST = "localhost:5437"
        GITEA__database__NAME = "gitea"
        GITEA__database__USER = "gitea"
        GITEA__database__SSL_MODE = "disable"
        
        # Server configuration - HTTPS only, no SSH
        GITEA__server__DOMAIN = "gitea.lab.hartr.net"
        GITEA__server__HTTP_PORT = "3001"
        GITEA__server__ROOT_URL = "https://gitea.lab.hartr.net"
        GITEA__server__DISABLE_SSH = "true"
        GITEA__server__START_SSH_SERVER = "false"
        GITEA__server__OFFLINE_MODE = "false"
        
        # Trust Authelia's forwarded authentication headers for SSO
        GITEA__service__ENABLE_REVERSE_PROXY_AUTHENTICATION = "true"
        GITEA__service__ENABLE_REVERSE_PROXY_AUTO_REGISTRATION = "true"
        GITEA__service__REVERSE_PROXY_AUTHENTICATION_USER = "Remote-User"
        GITEA__service__REVERSE_PROXY_AUTHENTICATION_EMAIL = "Remote-Email"
        GITEA__service__REVERSE_PROXY_AUTHENTICATION_FULL_NAME = "Remote-Name"
        GITEA__service__REVERSE_PROXY_LIMIT = "1"
        GITEA__service__REVERSE_PROXY_TRUSTED_PROXIES = "10.0.0.0/24"
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


