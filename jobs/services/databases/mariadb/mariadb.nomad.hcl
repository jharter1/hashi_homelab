job "mariadb" {
  datacenters = ["dc1"]
  type        = "service"

  spread {
    attribute = "${node.unique.name}"
  }

  constraint {
    attribute = "${node.unique.name}"
    value     = "dev-nomad-client-1"
  }

  group "mariadb" {
    count = 1

    network {
      mode = "host"
      port "db" {
        static = 3306
      }
    }

    volume "mariadb_data" {
      type      = "host"
      read_only = false
      source    = "mariadb_data"
    }

    task "mariadb" {
      driver = "docker"

      # Enable Vault workload identity for secrets access
      vault {}

      config {
        image        = "mariadb:11.2"
        network_mode = "host"
        ports        = ["db"]
        privileged   = true

        # Mount local directory to docker-entrypoint-initdb.d for SQL init files
        volumes = [
          "local:/docker-entrypoint-initdb.d"
        ]

        args = [
          "--character-set-server=utf8mb4",
          "--collation-server=utf8mb4_unicode_ci",
          "--innodb-buffer-pool-size=512M",
          "--max-connections=200",
          "--transaction-isolation=READ-COMMITTED",
          "--binlog-format=ROW",
        ]
      }

      volume_mount {
        volume      = "mariadb_data"
        destination = "/var/lib/mysql"
      }

      # Vault template for MariaDB root password
      template {
        destination = "secrets/mariadb.env"
        env         = true
        change_mode = "noop"
        data        = <<EOH
# MariaDB root password
MYSQL_ROOT_PASSWORD={{ with secret "secret/data/mariadb/admin" }}{{ .Data.data.password }}{{ end }}
EOH
      }

      # Initialization script to create databases, users, and allow root network access
      template {
        destination = "local/init-databases.sql"
        data        = <<EOH
-- Allow root to connect from any host (needed for Seafile initial setup)
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY '{{ with secret "secret/data/mariadb/admin" }}{{ .Data.data.password }}{{ end }}';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;

-- Seafile databases (requires 3 databases)
CREATE DATABASE IF NOT EXISTS `ccnet_db` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS `seafile_db` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS `seahub_db` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Create Seafile user
CREATE USER IF NOT EXISTS 'seafile'@'%' IDENTIFIED BY '{{ with secret "secret/data/mariadb/seafile" }}{{ .Data.data.password }}{{ end }}';

-- Grant permissions
GRANT ALL PRIVILEGES ON `ccnet_db`.* TO 'seafile'@'%';
GRANT ALL PRIVILEGES ON `seafile_db`.* TO 'seafile'@'%';
GRANT ALL PRIVILEGES ON `seahub_db`.* TO 'seafile'@'%';

-- BookStack database
CREATE DATABASE IF NOT EXISTS `bookstack` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Create BookStack user
CREATE USER IF NOT EXISTS 'bookstack'@'%' IDENTIFIED BY '{{ with secret "secret/data/mariadb/bookstack" }}{{ .Data.data.password }}{{ end }}';

-- Grant permissions
GRANT ALL PRIVILEGES ON `bookstack`.* TO 'bookstack'@'%';

FLUSH PRIVILEGES;
EOH
      }

      env {
        MYSQL_DATABASE               = "mysql"
        MYSQL_LOG_CONSOLE            = "true"
        MARIADB_AUTO_UPGRADE         = "1"
        MARIADB_DISABLE_UPGRADE_BACKUP = "1"
      }

      resources {
        cpu        = 500
        memory     = 256
        memory_max = 512
      }

      service {
        name = "mariadb"
        port = "db"
        tags = [
          "database",
          "mysql",
          "mariadb",
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
