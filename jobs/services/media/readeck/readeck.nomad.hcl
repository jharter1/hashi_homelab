job "readeck" {
  datacenters = ["dc1"]
  type        = "service"

  spread {
    attribute = "${node.unique.name}"
  }

  group "readeck" {
    count = 1

    network {
      mode = "host"
      port "http" {
        static = 8084
      }
    }

    volume "readeck_data" {
      type      = "host"
      read_only = false
      source    = "readeck_data"
    }

    task "readeck" {
      driver = "docker"

      config {
        image        = "registry.lab.hartr.net/readeck:latest"
        network_mode = "host"
        ports        = ["http"]
        dns_servers  = ["10.0.0.10", "1.1.1.1"]
      }

      volume_mount {
        volume      = "readeck_data"
        destination = "/readeck"
      }

      env {
        READECK_SERVER_HOST            = "0.0.0.0"
        READECK_SERVER_PORT            = "8084"
        READECK_LOG_LEVEL              = "info"
        READECK_SERVER_ALLOWED_HOSTS   = "readeck.lab.hartr.net"
        READECK_USE_X_FORWARDED_FOR    = "true"
      }

      resources {
        cpu        = 100
        memory     = 128
        memory_max = 256
      }

      service {
        name = "readeck"
        port = "http"
        tags = [
          "read-later",
          "articles",
          "traefik.enable=true",
          "traefik.http.routers.readeck.rule=Host(`readeck.lab.hartr.net`)",
          "traefik.http.routers.readeck.entrypoints=websecure",
          "traefik.http.routers.readeck.tls=true",
          "traefik.http.routers.readeck.tls.certresolver=letsencrypt",
          "traefik.http.routers.readeck.middlewares=authelia@file",
        ]
        check {
          type     = "http"
          path     = "/"
          interval = "30s"
          timeout  = "5s"
        }
      }
    }
  }
}
