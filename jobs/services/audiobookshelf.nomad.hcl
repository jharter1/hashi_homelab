job "audiobookshelf" {
  datacenters = ["dc1"]
  type        = "service"

  group "audiobookshelf" {
    count = 1

    network {
      mode = "host"
      port "http" {
        static = 13378
      }
    }

    restart {
      attempts = 3
      delay    = "30s"
      interval = "5m"
      mode     = "fail"
    }

    update {
      max_parallel     = 1
      health_check     = "checks"
      min_healthy_time = "10s"
      healthy_deadline = "5m"
      auto_revert      = true
    }

    # Config volume - stores application configuration
    volume "config" {
      type      = "host"
      source    = "audiobookshelf_config"
      read_only = false
    }

    # Metadata volume - stores book metadata, covers, etc.
    volume "metadata" {
      type      = "host"
      source    = "audiobookshelf_metadata"
      read_only = false
    }

    # Audiobooks volume - stores actual audiobook files
    volume "audiobooks" {
      type      = "host"
      source    = "audiobookshelf_audiobooks"
      read_only = false
    }

    # Podcasts volume - stores podcast files
    volume "podcasts" {
      type      = "host"
      source    = "audiobookshelf_podcasts"
      read_only = false
    }

    task "audiobookshelf" {
      driver = "docker"

      volume_mount {
        volume      = "config"
        destination = "/config"
        read_only   = false
      }

      volume_mount {
        volume      = "metadata"
        destination = "/metadata"
        read_only   = false
      }

      volume_mount {
        volume      = "audiobooks"
        destination = "/audiobooks"
        read_only   = false
      }

      volume_mount {
        volume      = "podcasts"
        destination = "/podcasts"
        read_only   = false
      }

      env {
        PORT         = "13378"
        TZ           = "America/Chicago"
        AUDIOBOOKSHELF_UID = "1000"
        AUDIOBOOKSHELF_GID = "1000"
        # Increase max file upload size to 5GB for large audiobooks
        MAX_FILE_SIZE = "5368709120"
      }

      config {
        image        = "ghcr.io/advplyr/audiobookshelf:latest"
        network_mode = "host"
        
        # Use Pi-hole for DNS resolution
        dns_servers = ["10.0.0.10", "1.1.1.1"]
      }

      resources {
        cpu    = 1000
        memory = 2048
      }

      service {
        name = "audiobookshelf"
        port = "http"

        tags = [
          "traefik.enable=true",
          "traefik.http.routers.audiobookshelf.rule=Host(`audiobookshelf.home`)",
          "traefik.http.routers.audiobookshelf.entrypoints=web",
        ]

        check {
          type     = "http"
          path     = "/healthcheck"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}
