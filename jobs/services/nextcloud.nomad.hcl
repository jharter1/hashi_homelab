job "nextcloud" {
  datacenters = ["dc1"]
  type        = "service"

  group "nextcloud" {
    count = 1

    network {
      port "http" {
        to = 80
      }
    }

    volume "nextcloud_data" {
      type      = "host"
      read_only = false
      source    = "nextcloud_data"
    }

    volume "nextcloud_config" {
      type      = "host"
      read_only = false
      source    = "nextcloud_config"
    }

    task "nextcloud" {
      driver = "docker"

      # Enable Vault workload identity for secrets access
      vault {}

      config {
        image = "nextcloud:latest"
        ports = ["http"]
      }

      volume_mount {
        volume      = "nextcloud_data"
        destination = "/var/www/html/data"
      }

      volume_mount {
        volume      = "nextcloud_config"
        destination = "/var/www/html/config"
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
        # PostgreSQL database configuration
        POSTGRES_HOST = "postgresql.service.consul"
        POSTGRES_DB   = "nextcloud"
        POSTGRES_USER = "nextcloud"
        # POSTGRES_PASSWORD comes from Vault template above

        # Nextcloud configuration
        NEXTCLOUD_TRUSTED_DOMAINS = "nextcloud.home 10.0.0.60 10.0.0.61 10.0.0.62"
        
        # Optional: Configure MinIO as object storage backend
        # NEXTCLOUD_OBJECTSTORE_S3_HOST = "s3.home"
        # NEXTCLOUD_OBJECTSTORE_S3_BUCKET = "nextcloud"
        # NEXTCLOUD_OBJECTSTORE_S3_KEY = "minioadmin"
        # NEXTCLOUD_OBJECTSTORE_S3_SECRET = "minioadmin"
        # NEXTCLOUD_OBJECTSTORE_S3_USE_SSL = "false"
        # NEXTCLOUD_OBJECTSTORE_S3_REGION = "us-east-1"
      }

      resources {
        cpu    = 1000
        memory = 1024
      }

      service {
        name = "nextcloud"
        port = "http"
        tags = [
          "storage",
          "file-sync",
          "traefik.enable=true",
          "traefik.http.routers.nextcloud.rule=Host(`nextcloud.home`)",
          "traefik.http.routers.nextcloud.entrypoints=web",
        ]
        check {
          type     = "http"
          path     = "/status.php"
          interval = "30s"
          timeout  = "5s"
        }
      }
    }
  }
}

