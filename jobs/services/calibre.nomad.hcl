job "calibre" {
  datacenters = ["dc1"]

  group "calibre-group" {
    count = 1

    network {
      port "http" {
        to = 8083
      }
    }

    volume "calibre_data" {
      type      = "host"
      read_only = false
      source    = "calibre_data"
    }

    service {
      name = "calibre-web"
      port = "http"
      
      tags = [
        "traefik.enable=true",
        "traefik.http.routers.calibre.rule=Host(`calibre.home`)",
        "traefik.http.routers.calibre.entrypoints=web",
      ]

      check {
        name     = "calibre-health"
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "10s"
      }
    }

    task "calibre-web" {
      driver = "docker"
      config {
        image = "linuxserver/calibre-web:latest"
        ports = ["http"]
        volumes = [
          "local/calibre-config:/config"
        ]
      }

      volume_mount {
        volume      = "calibre_data"
        destination = "/books"
        read_only   = false
      }

      env {
        PUID = "1000"
        PGID = "1000"
        TZ   = "America/Chicago"
        DOCKER_MODS = "linuxserver/mods:universal-calibre"
      }

      restart {
      attempts = 3
      interval = "5m"
      delay    = "25s"
      mode     = "fail"
    }
      resources {
        cpu    = 500
        memory = 1024
      }
    }
  }
}