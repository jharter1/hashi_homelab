job "minio" {
  datacenters = ["dc1"]
  type        = "service"

  group "minio" {
    count = 1

    network {
      mode = "host"
      port "api" {
        static = 9000
      }
      port "console" {
        static = 9001
      }
    }

    volume "minio_data" {
      type      = "host"
      read_only = false
      source    = "minio_data"
    }

    task "minio" {
      driver = "docker"

      env {
        MINIO_ROOT_USER = "minioadmin"
        MINIO_ROOT_PASSWORD = "minioadmin"
        MINIO_BROWSER_REDIRECT_URL = "http://minio.home:9001"
      }

      config {
        image        = "minio/minio:RELEASE.2023-09-04T19-57-37Z"
        network_mode = "host"

        args = [
          "server",
          "/data",
          "--address",
          ":9000",
          "--console-address",
          ":9001",
        ]
      }

      volume_mount {
        volume      = "minio_data"
        destination = "/data"
      }

      resources {
        cpu    = 500
        memory = 512
      }

      service {
        name = "minio-api"
        port = "api"
        tags = [
          "storage",
          "s3",
          "traefik.enable=true",
          "traefik.http.routers.minio-api.rule=Host(`s3.lab.hartr.net`)",
          "traefik.http.routers.minio-api.entrypoints=websecure",
          "traefik.http.routers.minio-api.tls=true",
          "traefik.http.routers.minio-api.tls.certresolver=letsencrypt",
          "traefik.http.routers.minio-api.tls=true",
        ]
        check {
          type     = "tcp"
          interval = "10s"
          timeout  = "2s"
        }
      }

      service {
        name = "minio-console"
        port = "console"
        tags = [
          "storage",
          "minio",
          "traefik.enable=true",
          "traefik.http.routers.minio-console.rule=Host(`minio.lab.hartr.net`)",
          "traefik.http.routers.minio-console.entrypoints=websecure",
          "traefik.http.routers.minio-console.tls=true",
          "traefik.http.routers.minio-console.tls.certresolver=letsencrypt",
          "traefik.http.routers.minio-console.tls=true",
          "traefik.http.routers.minio-console.middlewares=authelia@file",
        ]
        check {
          type     = "http"
          path     = "/minio/health/live"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}
