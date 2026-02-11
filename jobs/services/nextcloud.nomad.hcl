job "nextcloud" {
  datacenters = ["dc1"]
  type        = "service"

  group "nextcloud" {
    count = 1

    network {
      port "http" {
        to = 443
      }
    }

    task "nextcloud" {
      driver = "docker"

      # Enable Vault workload identity for secrets access
      vault {}

      config {
        image = "linuxserver/nextcloud:latest"
        ports = ["http"]
        
        # Use Docker-managed volume for better rootless compatibility
        volumes = [
          "nextcloud-data:/config"
        ]
      }

      # Vault template for database password
      template {
        destination = "secrets/db.env"
        env         = true
        data        = <<EOH
POSTGRES_PASSWORD={{ with secret "secret/data/postgres/nextcloud" }}{{ .Data.data.password }}{{ end }}
EOH
      }

      env {
        # LinuxServer.io PUID/PGID for rootless Docker compatibility
        PUID = "1000"
        PGID = "1000"
        TZ   = "America/Chicago"

        # PostgreSQL database configuration
        POSTGRES_HOST = "postgresql.home"
        POSTGRES_DB   = "nextcloud"
        POSTGRES_USER = "nextcloud"
        # POSTGRES_PASSWORD comes from Vault template above
      }

      resources {
        cpu    = 1000
        memory = 1536
      }

      service {
        name = "nextcloud"
        port = "http"
        tags = [
          "storage",
          "file-sync",
          "traefik.enable=true",
          "traefik.http.routers.nextcloud.rule=Host(`nextcloud.lab.hartr.net`)",
          "traefik.http.routers.nextcloud.entrypoints=websecure",
          "traefik.http.routers.nextcloud.tls=true",
          "traefik.http.routers.nextcloud.tls.certresolver=letsencrypt",
        ]
        check {
          type     = "tcp"
          interval = "30s"
          timeout  = "5s"
        }
      }
    }
  }
}


