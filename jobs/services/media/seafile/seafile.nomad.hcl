job "seafile" {
  datacenters = ["dc1"]
  type        = "service"

  group "seafile" {
    count = 1

    network {
      port "http" {
        to = 80  # Container port - Nomad will assign a random host port
      }
    }

    volume "seafile_data" {
      type      = "host"
      read_only = false
      source    = "seafile_data"
    }

    task "seafile" {
      driver = "docker"

      # Enable Vault workload identity for secrets access
      vault {}

      config {
        image      = "seafileltd/seafile-mc:11.0-latest"
        ports      = ["http"]
        privileged = true
      }

      volume_mount {
        volume      = "seafile_data"
        destination = "/shared"
      }

      # Vault template for database password
      template {
        destination = "secrets/db.env"
        env         = true
        data        = <<EOH
DB_ROOT_PASSWD={{ with secret "secret/data/mariadb/admin" }}{{ .Data.data.password }}{{ end }}
EOH
      }

      env {
        DB_HOST     = "10.0.0.60"
        DB_PORT     = "3306"
        TIME_ZONE   = "America/Chicago"
        
        # Admin account
        SEAFILE_ADMIN_EMAIL    = "admin@lab.hartr.net"
        SEAFILE_ADMIN_PASSWORD = "changeme_after_first_login"
        
        # Server URL
        SEAFILE_SERVER_LETSENCRYPT = "false"
        SEAFILE_SERVER_HOSTNAME    = "seafile.lab.hartr.net"
      }

      resources {
        cpu    = 1000
        memory = 1536
      }

      service {
        name = "seafile"
        port = "http"
        tags = [
          "storage",
          "file-sync",
          "traefik.enable=true",
          "traefik.http.routers.seafile.rule=Host(`seafile.lab.hartr.net`)",
          "traefik.http.routers.seafile.entrypoints=websecure",
          "traefik.http.routers.seafile.tls=true",
          "traefik.http.routers.seafile.tls.certresolver=letsencrypt",
          "traefik.http.routers.seafile.middlewares=authelia@file",
        ]
        check {
          type     = "http"
          path     = "/api2/ping/"
          interval = "30s"
          timeout  = "5s"
        }
      }
    }
  }
}
