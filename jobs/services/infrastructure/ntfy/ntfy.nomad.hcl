job "ntfy" {
  datacenters = ["dc1"]
  type        = "service"

  spread {
    attribute = "${node.unique.name}"
  }

  group "ntfy" {
    count = 1

    network {
      mode = "host"
      port "http" {
        static = 8085
      }
    }

    volume "ntfy_data" {
      type      = "host"
      read_only = false
      source    = "ntfy_data"
    }

    task "ntfy" {
      driver = "docker"

      config {
        image        = "binwiederhier/ntfy:latest"
        network_mode = "host"
        ports        = ["http"]
        args         = ["serve"]
      }

      env {
        NTFY_LISTEN_HTTP  = ":8085"
        NTFY_CACHE_FILE   = "/var/lib/ntfy/cache.db"
        NTFY_BEHIND_PROXY = "true"
        NTFY_BASE_URL     = "https://ntfy.lab.hartr.net"
      }

      volume_mount {
        volume      = "ntfy_data"
        destination = "/var/lib/ntfy"
      }

      resources {
        cpu        = 50
        memory     = 64
        memory_max = 128
      }

      service {
        name = "ntfy"
        port = "http"

        check {
          type     = "http"
          path     = "/v1/health"
          interval = "30s"
          timeout  = "5s"
        }

        tags = [
          "notifications",
          "traefik.enable=true",
          "traefik.http.routers.ntfy.rule=Host(`ntfy.lab.hartr.net`)",
          "traefik.http.routers.ntfy.entrypoints=websecure",
          "traefik.http.routers.ntfy.tls=true",
          "traefik.http.routers.ntfy.tls.certresolver=letsencrypt",
          "traefik.http.routers.ntfy.middlewares=authelia@file",
        ]
      }
    }
  }
}
