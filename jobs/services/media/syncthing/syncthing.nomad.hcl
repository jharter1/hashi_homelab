job "syncthing" {
  datacenters = ["dc1"]
  type        = "service"

  spread {
    attribute = "${node.unique.name}"
  }

  group "syncthing" {
    count = 1

    network {
      mode = "host"
      port "web" {
        static = 8384
      }
      port "listen" {
        static = 22000
      }
      port "discovery" {
        static = 21027
      }
    }

    volume "syncthing_config" {
      type      = "host"
      read_only = false
      source    = "syncthing_config"
    }

    volume "syncthing_data" {
      type      = "host"
      read_only = false
      source    = "syncthing_data"
    }

    task "syncthing" {
      driver = "docker"
      
      user = "1000:1000"

      config {
        image        = "syncthing/syncthing:latest"
        network_mode = "host"
        ports        = ["web", "listen", "discovery"]
      }

      volume_mount {
        volume      = "syncthing_config"
        destination = "/var/syncthing"
      }

      volume_mount {
        volume      = "syncthing_data"
        destination = "/data"
      }

      resources {
        cpu        = 200
        memory     = 64
        memory_max = 256
      }

      service {
        name = "syncthing"
        port = "web"
        tags = [
          "storage",
          "file-sync",
          "traefik.enable=true",
          "traefik.http.routers.syncthing.rule=Host(`syncthing.lab.hartr.net`)",
          "traefik.http.routers.syncthing.entrypoints=websecure",
          "traefik.http.routers.syncthing.tls=true",
          "traefik.http.routers.syncthing.tls.certresolver=letsencrypt",
        ]
        check {
          type     = "http"
          path     = "/rest/noauth/health"
          interval = "30s"
          timeout  = "5s"
        }
      }
    }
  }
}