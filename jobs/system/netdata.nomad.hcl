job "netdata" {
  datacenters = ["dc1"]
  type        = "system"

  group "netdata" {
    network {
      port "http" {
        to = 19999
      }
    }

    # Node-specific service
    service {
      name = "netdata-${node.unique.name}"
      port = "http"
      
      tags = [
        "traefik.enable=true",
        "traefik.http.routers.netdata-${node.unique.name}.rule=Host(`${node.unique.name}-netdata.home`)",
        "traefik.http.routers.netdata-${node.unique.name}.entrypoints=web",
      ]

      check {
        name     = "netdata-health"
        type     = "http"
        path     = "/api/v1/info"
        interval = "30s"
        timeout  = "5s"
      }
    }

    # Generic load-balanced service
    service {
      name = "netdata"
      port = "http"
      
      tags = [
        "traefik.enable=true",
        "traefik.http.routers.netdata.rule=Host(`netdata.home`)",
        "traefik.http.routers.netdata.entrypoints=web",
      ]

      check {
        name     = "netdata-health-lb"
        type     = "http"
        path     = "/api/v1/info"
        interval = "30s"
        timeout  = "5s"
      }
    }

    task "netdata" {
      driver = "docker"

      config {
        image = "netdata/netdata:latest"
        ports = ["http"]
        
        volumes = [
          "/proc:/host/proc:ro",
          "/sys:/host/sys:ro",
          "/var/run/docker.sock:/var/run/docker.sock:ro"
        ]
        
        cap_add = ["SYS_PTRACE"]
      }

      env {
        DOCKER_HOST = "unix:///var/run/docker.sock"
      }

      resources {
        cpu    = 200
        memory = 256
      }
    }
  }
}
