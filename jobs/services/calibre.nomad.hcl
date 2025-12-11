job "calibre" {
  datacenters = ["dc1"]

  group "calibre-group" {
    count = 1

    network {
      port "http" {
        to = 8083
      }
    }

    task "calibre-web" {
      driver = "docker"
      config {
        image = "linuxserver/calibre-web:latest"
        ports = ["http"]
        volumes = [
          "local/calibre/config:/config",
          "local/calibre/books:/books"
        ]
        restart {
          attempts = 3
          interval = "5m"
          delay    = "25s"
          mode     = "fail"
        }
      }
      resources {
        cpu    = 500
        memory = 1024
      }
    }
  }
}