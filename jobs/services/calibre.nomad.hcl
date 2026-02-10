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

    volume "calibre_config" {
      type      = "host"
      read_only = false
      source    = "calibre_config"
    }

    service {
      name = "calibre-web"
      port = "http"
      
      tags = [
        "traefik.enable=true",
        "traefik.http.routers.calibre.rule=Host(`calibre.lab.hartr.net`)",
        "traefik.http.routers.calibre.entrypoints=websecure",
        "traefik.http.routers.calibre.tls=true",
        "traefik.http.routers.calibre.tls.certresolver=letsencrypt",
        "traefik.http.routers.calibre.middlewares=authelia@file",
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
        privileged = true
      }

      volume_mount {
        volume      = "calibre_config"
        destination = "/config"
        read_only   = false
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
        memory = 768
      }
    }
  }
}