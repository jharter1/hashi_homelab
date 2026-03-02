job "registry" {
  datacenters = ["dc1"]
  type        = "service"

  # Pin to client-1 — daemon.json mirror entries reference a stable address,
  # and Traefik DNS (*.lab.hartr.net → 10.0.0.60) is already pinned there.
  constraint {
    attribute = "${node.unique.name}"
    value     = "dev-nomad-client-1"
  }

  group "registry" {
    count = 1

    network {
      mode = "host"
      port "http" {
        static = 5000
      }
    }

    volume "registry_data" {
      type      = "host"
      read_only = false
      source    = "registry_data"
    }

    update {
      max_parallel      = 1
      health_check      = "checks"
      min_healthy_time  = "10s"
      healthy_deadline  = "2m"
      progress_deadline = "5m"
      auto_revert       = true
    }

    task "registry" {
      driver = "docker"

      config {
        image        = "registry:2"
        network_mode = "host"
        ports        = ["http"]
      }

      volume_mount {
        volume      = "registry_data"
        destination = "/var/lib/registry"
      }

      env {
        REGISTRY_HTTP_ADDR                        = "0.0.0.0:5000"
        # Tell the registry its public URL so redirect URLs in blob responses
        # point to the Traefik-fronted hostname, not the internal address.
        REGISTRY_HTTP_HOST                        = "https://registry.lab.hartr.net"
        REGISTRY_STORAGE_FILESYSTEM_ROOTDIRECTORY = "/var/lib/registry"
        REGISTRY_STORAGE_DELETE_ENABLED           = "true"
        REGISTRY_LOG_LEVEL                        = "warn"
      }

      resources {
        cpu        = 100
        memory     = 128
        memory_max = 512
      }

      service {
        name = "registry"
        port = "http"

        tags = [
          "traefik.enable=true",
          "traefik.http.routers.registry.rule=Host(`registry.lab.hartr.net`)",
          "traefik.http.routers.registry.entrypoints=websecure",
          "traefik.http.routers.registry.tls=true",
          "traefik.http.routers.registry.tls.certresolver=letsencrypt",
          # No Authelia — Docker clients use their own auth, not browser redirects.
          # Registry is internal-only; Traefik/firewall provides perimeter.
        ]

        check {
          type     = "http"
          path     = "/v2/"
          interval = "15s"
          timeout  = "5s"
        }
      }
    }
  }
}
