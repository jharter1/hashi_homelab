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
        
        # Mount custom config override and SSO setup script
        volumes = [
          "local/custom.config.php:/var/www/html/config/custom.config.php",
          "local/setup-sso.sh:/docker-entrypoint-hooks.d/post-installation/setup-sso.sh"
        ]
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

      # Custom config override for trusted domains
      # Nextcloud automatically loads any PHP files in config/ directory
      template {
        destination = "local/custom.config.php"
        data        = <<EOH
<?php
$CONFIG = array (
  'trusted_domains' => 
  array (
    0 => 'localhost',
    1 => 'nextcloud.lab.hartr.net',
    2 => 'nextcloud.home',
    3 => '10.0.0.60',
    4 => '10.0.0.61',
    5 => '10.0.0.62',
  ),
  'overwrite.cli.url' => 'https://nextcloud.lab.hartr.net',
  'overwriteprotocol' => 'https',
  
  // Authelia SSO Integration - trust reverse proxy headers
  'trusted_proxies' => array('10.0.0.60', '10.0.0.61', '10.0.0.62'),
  'forwarded_for_headers' => array('HTTP_X_FORWARDED_FOR'),
);
EOH
      }

      # Setup script for Authelia SSO integration
      template {
        destination = "local/setup-sso.sh"
        perms       = "755"
        data        = <<EOH
#!/bin/bash
set -e

# Wait for Nextcloud to be ready
while [ ! -f /var/www/html/config/config.php ]; do
  echo "Waiting for Nextcloud initialization..."
  sleep 5
done

# Give Nextcloud a bit more time to fully start
sleep 10

cd /var/www/html

# Install and enable user_backend_sql_raw app for SSO
if ! sudo -u www-data php occ app:list | grep -q "user_backend_sql_raw"; then
  echo "Installing SSO support..."
  
  # For Authelia, we use the simpler approach of trusting Remote-User header
  # This requires the user to exist in Nextcloud first
  
  # Set the remote user backend
  sudo -u www-data php occ config:system:set trusted_proxies 0 --value="10.0.0.60"
  sudo -u www-data php occ config:system:set trusted_proxies 1 --value="10.0.0.61"
  sudo -u www-data php occ config:system:set trusted_proxies 2 --value="10.0.0.62"
  
  # Configure Apache to accept Remote-User header from Authelia
  sudo -u www-data php occ config:system:set auth.bruteforce.protection.enabled --value=false --type=boolean
  
  echo "SSO configuration complete"
fi

echo "Nextcloud SSO setup finished"
EOH
      }

      env {
        # PostgreSQL database configuration
        POSTGRES_HOST = "postgresql.home"
        POSTGRES_DB   = "nextcloud"
        POSTGRES_USER = "nextcloud"
        # POSTGRES_PASSWORD comes from Vault template above

        # Nextcloud configuration
        NEXTCLOUD_TRUSTED_DOMAINS = "nextcloud.home nextcloud.lab.hartr.net 10.0.0.60 10.0.0.61 10.0.0.62"
        
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
          "traefik.http.routers.nextcloud.middlewares=authelia@file",
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


