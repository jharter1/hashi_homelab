job "speedtest" {
  datacenters = ["dc1"]
  type        = "service"

  spread {
    attribute = "${node.unique.name}"
  }

  group "speedtest" {
    count = 1

    network {
      mode = "host"
      port "http" {
        static = 8765
      }
      port "db" {
        static = 5439
      }
    }

    volume "speedtest_data" {
      type      = "host"
      read_only = false
      source    = "speedtest_data"
    }

    volume "speedtest_postgres_data" {
      type      = "host"
      read_only = false
      source    = "speedtest_postgres_data"
    }

    # PostgreSQL database
    task "postgres" {
      driver = "docker"

      # Ensure postgres is ready before speedtest starts
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
        args         = ["-p", "5439"]
      }

      volume_mount {
        volume      = "speedtest_postgres_data"
        destination = "/var/lib/postgresql/data"
      }

      template {
        destination = "secrets/postgres.env"
        env         = true
        change_mode = "noop"
        data        = <<EOH
POSTGRES_DB=speedtest
POSTGRES_USER=speedtest
POSTGRES_PASSWORD={{ with secret "secret/data/postgres/speedtest" }}{{ .Data.data.password }}{{ end }}
EOH
      }

      env {
        PGDATA = "/var/lib/postgresql/data/pgdata"
        POSTGRES_HOST_AUTH_METHOD = "scram-sha-256"
        POSTGRES_PORT = "5439"
      }

      resources {
        cpu        = 200
        memory     = 32
        memory_max = 128
      }

      service {
        name = "speedtest-postgres"
        port = "db"
        tags = ["database", "postgres"]
        
        check {
          type     = "tcp"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }

    task "speedtest" {
      driver = "docker"

      # Enable Vault workload identity for secrets access
      vault {}

      config {
        image        = "lscr.io/linuxserver/speedtest-tracker:latest"
        network_mode = "host"
        ports        = ["http"]
        privileged   = true

        # Mount custom nginx config for port 8765
        mount {
          type   = "bind"
          source = "local/nginx-default.conf"
          target = "/config/nginx/site-confs/default.conf"
        }
      }

      volume_mount {
        volume      = "speedtest_data"
        destination = "/config"
      }

      # Vault template for database password
      template {
        destination = "secrets/db.env"
        env         = true
        change_mode = "noop"
        data        = <<EOH
DB_PASSWORD={{ with secret "secret/data/postgres/speedtest" }}{{ .Data.data.password }}{{ end }}
EOH
      }

      # Custom nginx config for port 8765 - mirrors linuxserver default but HTTP only
      template {
        destination = "local/nginx-default.conf"
        data        = <<EOH
server {
    listen 8765 default_server;
    listen [::]:8765 default_server;

    server_name _;

    set {{`$`}}root /app/www/public;
    if (!-d /app/www/public) {
        set {{`$`}}root /config/www;
    }
    root {{`$`}}root;
    index index.html index.htm index.php;

    client_max_body_size 0;

    location / {
        try_files {{`$`}}uri {{`$`}}uri/ /index.html /index.htm /index.php{{`$`}}is_args{{`$`}}args;
    }

    location ~ ^(.+\.php)(.*){{`$`}} {
        fastcgi_split_path_info ^(.+\.php)(.*){{`$`}};
        if (!-f {{`$`}}document_root{{`$`}}fastcgi_script_name) { return 404; }
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_index index.php;
        fastcgi_buffers 16 4k;
        fastcgi_buffer_size 16k;
        include /etc/nginx/fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOH
      }

      env {
        PUID = "1000"
        PGID = "1000"
        APP_KEY = "base64:4cVfJ7AmsGsW1DLHcn4VzvfA3bq6kOglrkTgVIZTKWU="
        APP_TIMEZONE = "America/Chicago"
        APP_URL = "https://speedtest.lab.hartr.net"
        # PostgreSQL configuration
        DB_CONNECTION = "pgsql"
        DB_HOST = "localhost"
        DB_PORT = "5439"
        DB_DATABASE = "speedtest"
        DB_USERNAME = "speedtest"
        SPEEDTEST_SCHEDULE = "0 */6 * * *"  # Every 6 hours
        SPEEDTEST_SERVERS = ""
        PRUNE_RESULTS_OLDER_THAN = "365"  # Keep results for 1 year
        CHART_DATETIME_FORMAT = "M/d H:i"
        DATETIME_FORMAT = "m/d/Y H:i:s"
        SKIP_CHECK_WEB_SERVER = "true"
      }

      resources {
        cpu        = 200
        memory     = 128
        memory_max = 512
      }

      service {
        name = "speedtest"
        port = "http"
        tags = [
          "traefik.enable=true",
          # UI router — protected by Authelia
          "traefik.http.routers.speedtest.rule=Host(`speedtest.lab.hartr.net`)",
          "traefik.http.routers.speedtest.entrypoints=websecure",
          "traefik.http.routers.speedtest.tls=true",
          "traefik.http.routers.speedtest.tls.certresolver=letsencrypt",
          "traefik.http.routers.speedtest.middlewares=authelia@file",
          # API router — no auth so homepage widget can query results
          # Priority is auto-calculated from rule length; the longer rule wins over the UI router
          "traefik.http.routers.speedtest-api.rule=Host(`speedtest.lab.hartr.net`) && PathPrefix(`/api/`)",
          "traefik.http.routers.speedtest-api.entrypoints=websecure",
          "traefik.http.routers.speedtest-api.tls=true",
          "traefik.http.routers.speedtest-api.tls.certresolver=letsencrypt",
        ]
        check {
          type     = "http"
          path     = "/"
          interval = "30s"
          timeout  = "10s"
          check_restart {
            limit = 3
            grace = "90s"
            ignore_warnings = false
          }
        }
      }
    }
  }
}
