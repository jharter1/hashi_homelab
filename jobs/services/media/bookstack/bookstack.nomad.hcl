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
      }

      volume_mount {
        volume      = "bookstack_config"
        destination = "/config"
      }

      # Vault template for database credentials
      template {
        destination = "secrets/db.env"
        env         = true
        data        = <<EOH
# Database password
DB_PASS={{ with secret "secret/data/mariadb/bookstack" }}{{ .Data.data.password }}{{ end }}
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
        DB_HOST = "localhost"
        DB_PORT = "3307"
        DB_DATABASE = "bookstack"
        DB_USER = "bookstack"
        # DB_PASS comes from Vault template

        # Port configuration (override default 80)
        APP_PORT = "8083"

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
