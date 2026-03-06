job "trilium" {
  datacenters = ["dc1"]
  type        = "service"

  group "trilium" {
    count = 1

    network {
      mode = "host"
      port "http" {
        static = 8087
      }
    }

    volume "trilium_data" {
      type      = "host"
      read_only = false
      source    = "trilium_data"
    }

    task "trilium" {
      driver = "docker"

      config {
        image        = "zadam/trilium:latest"
        network_mode = "host"
        ports        = ["http"]
        privileged   = true
      }

      volume_mount {
        volume      = "trilium_data"
        destination = "/home/node/trilium-data"
      }

      env {
        TRILIUM_PORT = "8087"
        TZ           = "America/Chicago"
        
        # Authelia SSO note: Trilium doesn't natively support proxy auth headers
        # It uses its own authentication system. Consider using same password for consistency.
        # For full SSO, would need custom proxy or Trilium plugin development.
      }

      resources {
        cpu    = 500
        memory = 512
      }

      service {
        name = "trilium"
        port = "http"
        tags = [
          "knowledge-management",
          "notes",
          "traefik.enable=true",
          "traefik.http.routers.trilium.rule=Host(`trilium.lab.hartr.net`)",
          "traefik.http.routers.trilium.entrypoints=websecure",
          "traefik.http.routers.trilium.tls=true",
          "traefik.http.routers.trilium.tls.certresolver=letsencrypt",
          "traefik.http.routers.trilium.middlewares=authelia@file",
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
