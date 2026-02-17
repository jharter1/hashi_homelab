job "bookstack" {
  datacenters = ["dc1"]
  type        = "service"

  update {
    max_parallel     = 1
    min_healthy_time = "30s"
    healthy_deadline = "15m"
    progress_deadline = "20m"
    auto_revert      = false
  }

  group "bookstack" {
    count = 1

    # Prevent multiple instances on same node to avoid port conflicts
    constraint {
      distinct_hosts = true
    }

    network {
      mode = "host"
      port "http" {
        static = 8083
      }
      port "db" {
        static = 3307
      }
    }

    volume "bookstack_config" {
      type      = "host"
      read_only = false
      source    = "bookstack_config"
    }

    volume "bookstack_mariadb_data" {
      type      = "host"
      read_only = false
      source    = "bookstack_mariadb_data"
    }

    # MariaDB database sidecar
    task "mariadb" {
      driver = "docker"

      # Ensure mariadb is ready before bookstack starts
      lifecycle {
        hook    = "prestart"
        sidecar = true
      }

      vault {}

      config {
        image        = "mariadb:11.2"
        network_mode = "host"
        ports        = ["db"]
        privileged   = true
      }

      volume_mount {
        volume      = "bookstack_mariadb_data"
        destination = "/var/lib/mysql"
      }

      template {
        destination = "secrets/mariadb.env"
        env         = true
        data        = <<EOH
MYSQL_ROOT_PASSWORD={{ with secret "secret/data/mariadb/bookstack" }}{{ .Data.data.password }}{{ end }}
MYSQL_DATABASE=bookstack
MYSQL_USER=bookstack
MYSQL_PASSWORD={{ with secret "secret/data/mariadb/bookstack" }}{{ .Data.data.password }}{{ end }}
EOH
      }

      env {
        MYSQL_TCP_PORT = "3307"
      }

      resources {
        cpu    = 500
        memory = 256
      }

      service {
        name = "bookstack-mariadb"
        port = "db"
        tags = ["database", "mariadb"]
        
        check {
          type     = "tcp"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }

    task "bookstack" {
      driver = "docker"

      vault {}

      config {
        image        = "lscr.io/linuxserver/bookstack:latest"
        network_mode = "host"
        ports        = ["http"]
        privileged   = true
        
        # Mount custom nginx config for port 8083
        mount {
          type   = "bind"
          source = "local/nginx-default.conf"
          target = "/config/nginx/site-confs/default.conf"
        }
      }

      volume_mount {
        volume      = "bookstack_config"
        destination = "/config"
      }

      # Vault template for database and app credentials
      template {
        destination = "secrets/app.env"
        env         = true
        data        = <<EOH
# Database password - linuxserver.io uses DB_PASSWORD
DB_PASSWORD={{ with secret "secret/data/mariadb/bookstack" }}{{ .Data.data.password }}{{ end }}

# Application key (Laravel encryption key)
APP_KEY={{ with secret "secret/data/bookstack/app" }}{{ .Data.data.key }}{{ end }}
EOH
      }

      # Custom nginx config for port 8083
      template {
        destination = "local/nginx-default.conf"
        data        = <<EOH
server {
    listen 8083 default_server;
    listen [::]:8083 default_server;
    
    server_name _;
    
    root /app/www/public;
    index index.php index.html;
    
    client_max_body_size 0;
    
    location / {
        try_files {{`$`}}uri {{`$`}}uri/ /index.php{{`$`}}is_args{{`$`}}args;
    }
    
    location ~ \.php{{`$`}} {
        fastcgi_split_path_info ^(.+\.php)(/.+){{`$`}};
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_index index.php;
        include /etc/nginx/fastcgi_params;
        fastcgi_param SCRIPT_FILENAME {{`$`}}document_root{{`$`}}fastcgi_script_name;
        fastcgi_param PATH_INFO {{`$`}}fastcgi_path_info;
        fastcgi_param QUERY_STRING {{`$`}}query_string;
    }
    
    location ~ /\.ht {
        deny all;
    }
}
EOH
      }

      env {
        # LinuxServer.io PUID/PGID
        PUID = "1000"
        PGID = "1000"
        TZ   = "America/Chicago"

        # Application URL
        APP_URL = "https://bookstack.lab.hartr.net"

        # Database configuration - using dedicated MariaDB sidecar
        # Use 127.0.0.1 instead of localhost to force TCP connection
        # linuxserver.io uses DB_USERNAME not DB_USER
        DB_HOST = "127.0.0.1"
        DB_PORT = "3307"
        DB_DATABASE = "bookstack"
        DB_USERNAME = "bookstack"
        # DB_PASSWORD and APP_KEY come from Vault template

        # Mail configuration (optional - using log for local deployment)
        MAIL_DRIVER = "log"
        MAIL_FROM = "bookstack@lab.hartr.net"
        MAIL_FROM_NAME = "BookStack"

        # Cache and session
        CACHE_DRIVER = "file"
        SESSION_DRIVER = "file"

        # Queue configuration
        QUEUE_CONNECTION = "sync"
      }

      resources {
        cpu    = 500
        memory = 512
      }

      service {
        name = "bookstack"
        port = "http"
        tags = [
          "documentation",
          "wiki",
          "traefik.enable=true",
          "traefik.http.routers.bookstack.rule=Host(`bookstack.lab.hartr.net`)",
          "traefik.http.routers.bookstack.entrypoints=websecure",
          "traefik.http.routers.bookstack.tls=true",
          "traefik.http.routers.bookstack.tls.certresolver=letsencrypt",
        ]
        check {
          type     = "http"
          path     = "/login"
          interval = "30s"
          timeout  = "10s"
        }
      }
    }
  }
}
