job "uptime-kuma" {
  datacenters = ["dc1"]

  group "uptime-kuma-group" {
    count = 1

    network {
      port "http" {
        to = 3001
      }
    }

    task "uptime-kuma" {
      driver = "docker"
      
      config {
        image = "louislam/uptime-kuma:latest"
        ports = ["http"]
        volumes = [
          "local/uptime-kuma/data:/app/data"
        ]
      }

      restart {
        attempts = 3
        interval = "5m"
        delay    = "25s"
        mode     = "fail"
      }

      resources {
        cpu    = 500
        memory = 512
      }
    }
  }
}