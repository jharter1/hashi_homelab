job "drawio" {
  datacenters = ["dc1"]
  type        = "service"

  group "drawio" {
    count = 1

    network {
      mode = "host"
      port "http" {
        static = 8085
      }
    }

    task "drawio" {
      driver = "docker"

      config {
        image        = "jgraph/drawio:latest"
        network_mode = "host"
        ports        = ["http"]
        privileged   = true
      }

      env {
        # Disable Google Drive, OneDrive, etc. for privacy
        DRAWIO_GOOGLE_CLIENT_ID = ""
        DRAWIO_GOOGLE_APP_ID    = ""
        DRAWIO_ONEDRIVE_CLIENT_ID = ""
        DRAWIO_GITHUB_CLIENT_ID = ""
        DRAWIO_GITLAB_CLIENT_ID = ""
        
        # Configure for local deployment
        DRAWIO_BASE_URL = "https://diagrams.lab.hartr.net"
        DRAWIO_CSP_HEADER = "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:;"
      }

      resources {
        cpu    = 500
        memory = 256
      }

      service {
        name = "drawio"
        port = "http"
        tags = [
          "diagram",
          "drawing",
          "traefik.enable=true",
          "traefik.http.routers.drawio.rule=Host(`diagrams.lab.hartr.net`)",
          "traefik.http.routers.drawio.entrypoints=websecure",
          "traefik.http.routers.drawio.tls=true",
          "traefik.http.routers.drawio.tls.certresolver=letsencrypt",
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
