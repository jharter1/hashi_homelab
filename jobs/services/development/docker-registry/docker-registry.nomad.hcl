job "docker-registry" {
  datacenters = ["dc1"]
  type        = "service"

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

    task "registry" {
      driver = "docker"

      config {
        image        = "registry:2"
        network_mode = "host"
        ports        = ["http"]
        
        volumes = [
          # Config from centralized location
          "/mnt/nas/configs/infrastructure/docker-registry/config.yml:/etc/docker/registry/config.yml:ro",
        ]
      }

      volume_mount {
        volume      = "registry_data"
        destination = "/var/lib/registry"
      }

      # NOTE: Config now loaded from /mnt/nas/configs/infrastructure/docker-registry/config.yml
      # This eliminates the HEREDOC pattern and centralizes configuration

      env {
        REGISTRY_HTTP_ADDR = "0.0.0.0:5000"
      }

      resources {
        cpu    = 500
        memory = 512
      }

      service {
        name = "docker-registry"
        port = "http"
        tags = [
          "registry",
          "docker",
          "traefik.enable=true",
          "traefik.http.routers.registry.rule=Host(`registry.lab.hartr.net`)",
          "traefik.http.routers.registry.entrypoints=websecure",
          "traefik.http.routers.registry.tls=true",
          "traefik.http.routers.registry.tls.certresolver=letsencrypt",
          # Allow larger uploads for Docker images
          "traefik.http.middlewares.registry-buffering.buffering.maxRequestBodyBytes=2147483648",
          "traefik.http.routers.registry.middlewares=registry-buffering",
        ]
        check {
          type     = "http"
          path     = "/"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}
