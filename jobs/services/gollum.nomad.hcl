job "gollum" {
  datacenters = ["dc1"]
  type        = "service"

  group "gollum" {
    count = 1

    network {
      port "http" {
        to = 4567
      }
    }

    volume "gollum_data" {
      type      = "host"
      read_only = false
      source    = "gollum_data"
    }

    task "gollum" {
      driver = "docker"

      config {
        image = "gollumwiki/gollum:latest"
        ports = ["http"]
        args = [
          "/wiki",
          "--port", "4567",
          "--host", "0.0.0.0",
          "--allow-uploads"
        ]
      }

      volume_mount {
        volume      = "gollum_data"
        destination = "/wiki"
      }

      resources {
        cpu    = 200
        memory = 256
      }

      service {
        name = "gollum"
        port = "http"
        tags = [
          "documentation",
          "wiki",
          "traefik.enable=true",
          "traefik.http.routers.gollum.rule=Host(`wiki.lab.hartr.net`)",
          "traefik.http.routers.gollum.entrypoints=websecure",
          "traefik.http.routers.gollum.tls=true",
          "traefik.http.routers.gollum.tls.certresolver=letsencrypt",
          "traefik.http.routers.gollum.middlewares=authelia@file",
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
