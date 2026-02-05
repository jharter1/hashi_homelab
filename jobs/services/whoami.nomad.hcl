job "whoami" {
  datacenters = ["dc1"]
  type        = "service"

  group "demo" {
    count = 3 # Run 3 instances to demonstrate load balancing

    network {
      port "http" {
        to = 80
      }
    }

    service {
      name = "whoami"
      port = "http"
      tags = [
        "traefik.enable=true",
        "traefik.http.routers.whoami.rule=Host(`whoami.lab.hartr.net`)",
        "traefik.http.routers.whoami.entrypoints=websecure",
        "traefik.http.routers.whoami.tls=true",
        "traefik.http.routers.whoami.tls.certresolver=letsencrypt",
      ]
    }

    task "server" {
      driver = "docker"

      config {
        image = "traefik/whoami"
        ports = ["http"]
      }
    }
  }
}
