job "dozzle" {
  datacenters = ["dc1"]
  type        = "system"

  group "dozzle" {
    network {
      port "http" {
        to = 8080
      }
    }

    # Node-specific service
    service {
      name = "dozzle-${node.unique.name}"
      port = "http"
      
      tags = [
        "traefik.enable=true",
        "traefik.http.routers.dozzle-${node.unique.name}.rule=Host(`${node.unique.name}-dozzle.home`)",
        "traefik.http.routers.dozzle-${node.unique.name}.entrypoints=web",
      ]

      check {
        name     = "dozzle-alive"
        type     = "http"
        path     = "/"
        interval = "30s"
        timeout  = "5s"
      }
    }

    # Generic load-balanced service
    service {
      name = "dozzle"
      port = "http"
      
      tags = [
        "traefik.enable=true",
        "traefik.http.routers.dozzle.rule=Host(`dozzle.home`)",
        "traefik.http.routers.dozzle.entrypoints=web",
      ]

      check {
        name     = "dozzle-alive-lb"
        type     = "http"
        path     = "/"
        interval = "30s"
        timeout  = "5s"
      }
    }

    task "dozzle" {
      driver = "docker"

      config {
        image = "amir20/dozzle:latest"
        ports = ["http"]
        
        volumes = [
          "/var/run/docker.sock:/var/run/docker.sock:ro"
        ]
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
}
