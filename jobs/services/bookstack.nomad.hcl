job "bookstack" {
  datacenters = ["dc1"]
  type        = "service"

  group "bookstack" {
    count = 1

    network {
      mode = "host"
      port "http" {
        static = 8080
      }
      port "mysql" {
        static = 3306
      }
    }

    volume "bookstack_data" {
      type      = "host"
      read_only = false
      source    = "bookstack_data"
    }

    volume "bookstack_config" {
      type      = "host"
      read_only = false
      source    = "bookstack_config"
    }

    volume "bookstack_db_data" {
      type      = "host"
      read_only = false
      source    = "bookstack_db_data"
    }

    task "bookstack" {
      driver = "docker"

      config {
        image        = "lscr.io/linuxserver/bookstack:latest"
        network_mode = "host"
        ports        = ["http"]
      }

      volume_mount {
        volume      = "bookstack_data"
        destination = "/config"
      }

      volume_mount {
        volume      = "bookstack_config"
        destination = "/data"
      }

      env {
        PUID = "1000"
        PGID = "1000"
        TZ = "America/Chicago"
        APP_URL = "http://bookstack.home"
        # Database configuration - connects to bookstack-db task
        # Since both tasks use host network, use localhost
        DB_HOST = "127.0.0.1"
        DB_USER = "bookstack"
        DB_PASS = "bookstack"
        DB_DATABASE = "bookstack"
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
          "traefik.http.routers.bookstack.rule=Host(`bookstack.home`)",
          "traefik.http.routers.bookstack.entrypoints=web",
        ]
        check {
          type     = "http"
          path     = "/"
          interval = "30s"
          timeout  = "5s"
        }
      }
    }

    # BookStack requires MySQL/MariaDB database
    task "bookstack-db" {
      driver = "docker"

      config {
        image        = "linuxserver/mariadb:latest"
        network_mode = "host"
        ports        = ["mysql"]
      }

      volume_mount {
        volume      = "bookstack_db_data"
        destination = "/config"
      }

      env {
        PUID = "1000"
        PGID = "1000"
        TZ = "America/Chicago"
        MYSQL_ROOT_PASSWORD = "bookstack"
        MYSQL_DATABASE = "bookstack"
        MYSQL_USER = "bookstack"
        MYSQL_PASSWORD = "bookstack"
      }

      resources {
        cpu    = 500
        memory = 512
      }

      service {
        name = "bookstack-db"
        port = "mysql"
        tags = ["database", "mariadb"]
      }
    }
  }
}

