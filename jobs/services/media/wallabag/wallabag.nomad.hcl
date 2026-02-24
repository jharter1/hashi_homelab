job "wallabag" {
  datacenters = ["dc1"]
  type        = "service"

  group "wallabag" {
    count = 1

    network {
      mode = "host"
      port "http" {
        static = 8084
      }
      port "db" {
        static = 5434
      }
    }

    volume "wallabag_data" {
      type      = "host"
      read_only = false
      source    = "wallabag_data"
    }

    volume "wallabag_images" {
      type      = "host"
      read_only = false
      source    = "wallabag_images"
    }

    volume "wallabag_postgres_data" {
      type      = "host"
      read_only = false
      source    = "wallabag_postgres_data"
    }

    # PostgreSQL database
    task "postgres" {
      driver = "docker"

      # Ensure postgres is ready before wallabag starts
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
      }

      volume_mount {
        volume      = "wallabag_postgres_data"
        destination = "/var/lib/postgresql/data"
      }

      template {
        destination = "secrets/postgres.env"
        env         = true
        data        = <<EOH
POSTGRES_DB=wallabag
POSTGRES_USER=wallabag
POSTGRES_PASSWORD={{ with secret "secret/data/postgres/wallabag" }}{{ .Data.data.password }}{{ end }}
EOH
      }

      env {
        PGDATA = "/var/lib/postgresql/data/pgdata"
        POSTGRES_HOST_AUTH_METHOD = "scram-sha-256"
        PGPORT = "5434"
      }

      resources {
        cpu    = 500
        memory = 256
      }

      service {
        name = "wallabag-postgres"
        port = "db"
        tags = ["database", "postgres"]
        
        check {
          type     = "tcp"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }

    # Wallabag application (migrations must be run manually on first deploy)
    task "wallabag" {
      driver = "docker"

      vault {}

      config {
        image        = "wallabag/wallabag:latest"
        network_mode = "host"
        ports        = ["http"]
        privileged   = true

        # Override nginx.conf to listen on port 8084 instead of default 80
        mount {
          type   = "bind"
          source = "local/nginx.conf"
          target = "/etc/nginx/nginx.conf"
        }
      }

      volume_mount {
        volume      = "wallabag_data"
        destination = "/var/www/wallabag/data"
      }

      volume_mount {
        volume      = "wallabag_images"
        destination = "/var/www/wallabag/web/assets/images"
      }

      # Vault template for database and secrets
      template {
        destination = "secrets/app.env"
        env         = true
        data        = <<EOH
# Database configuration
SYMFONY__ENV__DATABASE_DRIVER=pdo_pgsql
SYMFONY__ENV__DATABASE_HOST=localhost
SYMFONY__ENV__DATABASE_PORT=5434
SYMFONY__ENV__DATABASE_NAME=wallabag
SYMFONY__ENV__DATABASE_USER=wallabag
SYMFONY__ENV__DATABASE_PASSWORD={{ with secret "secret/data/postgres/wallabag" }}{{ .Data.data.password }}{{ end }}

# Application secret
SYMFONY__ENV__SECRET={{ with secret "secret/data/wallabag/secret" }}{{ .Data.data.value }}{{ end }}
EOH
      }

      # Custom nginx config to listen on port 8084 (wallabag/wallabag image defaults to port 80)
      template {
        destination = "local/nginx.conf"
        data        = <<EOH
user nginx;
worker_processes 1;
pid /var/run/nginx.pid;

events {
    worker_connections 2048;
    multi_accept on;
    use epoll;
}

http {
    server_tokens off;
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 15;
    types_hash_max_size 2048;
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    access_log off;
    error_log off;
    gzip on;
    gzip_disable "msie6";
    open_file_cache max=100;
    client_max_body_size 100M;

    map {{`$`}}http_x_forwarded_proto {{`$`}}fe_https {
        default {{`$`}}https;
        https on;
    }

    upstream php-upstream {
        server 127.0.0.1:9000;
    }

    server {
        listen [::]:8084 ipv6only=off;
        server_name _;
        root /var/www/wallabag/web;

        location / {
            try_files {{`$`}}uri /app.php{{`$`}}is_args{{`$`}}args;
        }

        location ~ ^/app\.php(/|{{`$`}}) {
            fastcgi_pass php-upstream;
            fastcgi_split_path_info ^(.+\.php)(/.*{{`$`}});
            include fastcgi_params;
            fastcgi_param  SCRIPT_FILENAME  {{`$`}}realpath_root{{`$`}}fastcgi_script_name;
            fastcgi_param DOCUMENT_ROOT {{`$`}}realpath_root;
            fastcgi_read_timeout 300s;
            internal;
        }

        access_log /var/log/nginx/access.log;
        error_log /var/log/nginx/error.log;
    }
}

daemon off;
EOH
      }

      env {
        # Domain configuration
        SYMFONY__ENV__DOMAIN_NAME = "https://wallabag.lab.hartr.net"

        # Mailer configuration (optional - using null for local deployment)
        SYMFONY__ENV__MAILER_DSN = "null://localhost"
        SYMFONY__ENV__FROM_EMAIL = "wallabag@lab.hartr.net"

        # Registration and user settings
        SYMFONY__ENV__FOSUSER_REGISTRATION = "false"
        SYMFONY__ENV__FOSUSER_CONFIRMATION = "false"

        # Locale settings
        SYMFONY__ENV__LOCALE = "en"

        # Authelia SSO Integration - Trusted proxies for header authentication
        SYMFONY__ENV__TRUSTED_PROXIES = "10.0.0.0/24,127.0.0.1,REMOTE_ADDR"
      }

      resources {
        cpu    = 500
        memory = 512
      }

      service {
        name = "wallabag"
        port = "http"
        tags = [
          "read-later",
          "articles",
          "traefik.enable=true",
          "traefik.http.routers.wallabag.rule=Host(`wallabag.lab.hartr.net`)",
          "traefik.http.routers.wallabag.entrypoints=websecure",
          "traefik.http.routers.wallabag.tls=true",
          "traefik.http.routers.wallabag.tls.certresolver=letsencrypt",
          "traefik.http.routers.wallabag.middlewares=authelia@file",
        ]
        check {
          type     = "http"
          path     = "/"
          interval = "30s"
          timeout  = "10s"
          check_restart {
            limit = 3
            grace = "120s"
            ignore_warnings = false
          }
        }
      }
    }
  }
}
