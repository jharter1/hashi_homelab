job "cadvisor" {
  datacenters = ["dc1"]
  type        = "system"
  priority    = 50

  group "cadvisor" {
    network {
      mode = "host"
      port "http" {
        static = 8081
      }
    }

    task "cadvisor" {
      driver = "docker"

      config {
        image        = "gcr.io/cadvisor/cadvisor:v0.47.0"
        network_mode = "host"
        ports        = ["http"]

        # Specify custom port
        args = ["-port=8081"]

        # Required mounts for cAdvisor to monitor Docker
        volumes = [
          "/:/rootfs:ro",
          "/var/run:/var/run:ro",
          "/sys:/sys:ro",
          "/var/lib/docker/:/var/lib/docker:ro",
          "/dev/disk/:/dev/disk:ro",
        ]

        # Privileged mode required for cAdvisor to access container metrics
        privileged = true
      }

      resources {
        cpu    = 100
        memory = 128
      }

      service {
        name         = "cadvisor"
        port         = "http"
        address_mode = "host"

        tags = [
          "monitoring",
          "cadvisor",
        ]

        check {
          type     = "http"
          path     = "/metrics"
          interval = "10s"
          timeout  = "2s"
          port     = "http"
        }
      }
    }
  }
}
