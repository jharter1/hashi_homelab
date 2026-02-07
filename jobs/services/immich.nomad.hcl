job "immich" {
  datacenters = ["dc1"]
  type        = "service"

  group "immich-server" {
    count = 1

    network {
      mode = "host"
      port "http" {
        static = 2283
      }
    }

    volume "immich_upload" {
      type      = "host"
      read_only = false
      source    = "immich_upload"
    }

    volume "immich_postgres" {
      type      = "host"
      read_only = false
      source    = "immich_postgres"
    }

    # PostgreSQL database
    task "postgres" {
      driver = "docker"

      lifecycle {
        hook    = "prestart"
        sidecar = true
      }

      config {
        image = "tensorchord/pgvecto-rs:pg14-v0.2.0"
        network_mode = "host"
        command = "postgres"
        args = [
          "-c", "shared_preload_libraries=vectors.so",
          "-c", "search_path=\"$$user\", public, vectors",
          "-c", "logging_collector=on",
          "-c", "max_wal_size=2GB",
          "-c", "shared_buffers=512MB",
          "-c", "wal_compression=on"
        ]
      }

      volume_mount {
        volume      = "immich_postgres"
        destination = "/var/lib/postgresql/data"
      }

      env {
        POSTGRES_PASSWORD = "postgres"
        POSTGRES_USER = "postgres"
        POSTGRES_DB = "immich"
      }

      resources {
        cpu    = 500
        memory = 512
      }
    }

    # Immich server
    task "immich-server" {
      driver = "docker"

      config {
        image        = "ghcr.io/immich-app/immich-server:release"
        network_mode = "host"
        ports        = ["http"]
        command = "start.sh"
        args = ["immich"]
      }

      volume_mount {
        volume      = "immich_upload"
        destination = "/usr/src/app/upload"
      }

      env {
        # Server
        NODE_ENV = "production"
        LOG_LEVEL = "log"
        
        # Database
        DB_HOSTNAME = "127.0.0.1"
        DB_PORT = "5432"
        DB_USERNAME = "postgres"
        DB_PASSWORD = "postgres"
        DB_DATABASE_NAME = "immich"
        
        # Redis (shared service)
        REDIS_HOSTNAME = "redis.service.consul"
        REDIS_PORT = "6379"
        REDIS_DBINDEX = "0"
        
        # Upload
        UPLOAD_LOCATION = "/usr/src/app/upload"
        
        # Machine Learning (disabled, use separate job if needed)
        IMMICH_MACHINE_LEARNING_ENABLED = "false"
      }

      resources {
        cpu    = 500
        memory = 768
      }

      service {
        name = "immich"
        port = "http"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.immich.rule=Host(`immich.lab.hartr.net`)",
          "traefik.http.routers.immich.entrypoints=websecure",
          "traefik.http.routers.immich.tls=true",
          "traefik.http.routers.immich.tls.certresolver=letsencrypt",
          # Authelia SSO Protection
          "traefik.http.routers.immich.middlewares=forwardauth@file",
        ]
        check {
          type     = "http"
          path     = "/api/server-info/ping"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }

    # Immich microservices (thumbnail generation, metadata extraction, etc.)
    task "immich-microservices" {
      driver = "docker"

      config {
        image = "ghcr.io/immich-app/immich-server:release"
        network_mode = "host"
        command = "start.sh"
        args = ["microservices"]
      }

      volume_mount {
        volume      = "immich_upload"
        destination = "/usr/src/app/upload"
      }

      env {
        # Server
        NODE_ENV = "production"
        LOG_LEVEL = "log"
        
        # Database
        DB_HOSTNAME = "127.0.0.1"
        DB_PORT = "5432"
        DB_USERNAME = "postgres"
        DB_PASSWORD = "postgres"
        DB_DATABASE_NAME = "immich"
        
        # Redis (shared service)
        REDIS_HOSTNAME = "redis.service.consul"
        REDIS_PORT = "6379"
        REDIS_DBINDEX = "0"
        
        # Upload
        UPLOAD_LOCATION = "/usr/src/app/upload"
      }

      resources {
        cpu    = 500
        memory = 512
      }
    }
  }
}
