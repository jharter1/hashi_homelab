job "skopeo-sync" {
  datacenters = ["dc1"]
  type        = "batch"

  # Run daily at 3 AM Chicago time
  periodic {
    crons            = ["0 3 * * *"]
    prohibit_overlap = true
    time_zone        = "America/Chicago"
  }

  group "sync" {
    count = 1

    network {
      mode = "host"
    }

    # Give the sync plenty of time — large images (playwright, linuxserver) are ~2 GB each
    reschedule {
      attempts  = 1
      unlimited = false
    }

    restart {
      attempts = 1
      delay    = "30s"
      interval = "10m"
      mode     = "fail"
    }

    task "skopeo" {
      driver = "docker"

      # quay.io/skopeo/stable is the bootstrap image — it pulls direct until
      # we add it to the sync list and self-host it.
      config {
        image        = "quay.io/skopeo/stable:latest"
        network_mode = "host"
        # Run the sync against our local Traefik-fronted registry
        command      = "sync"
        args = [
          "--src", "yaml",
          "--dest", "docker",
          "--dest-tls-verify=true",
          "/local/sync-config.yaml",
          "registry.lab.hartr.net",
        ]
      }

      # Sync manifest — add images here to have them cached locally.
      # After editing, force an immediate sync with:
      #   nomad job periodic force skopeo-sync
      template {
        destination = "local/sync-config.yaml"
        data        = <<EOH
docker.io:
  images:
    # Databases
    postgres:
      - "16-alpine"
    redis:
      - "7-alpine"
    mariadb:
      - "11.2"
    # Observability
    grafana/grafana:
      - "latest"
    grafana/loki:
      - "3.6.0"
    grafana/tempo:
      - "latest"
    grafana/alloy:
      - "latest"
    prom/prometheus:
      - "latest"
    prom/alertmanager:
      - "latest"
    # Infrastructure
    traefik:
      - "v3.0"
    traefik/whoami:
      - "latest"
    minio/minio:
      - "RELEASE.2023-09-04T19-57-37Z"
    minio/mc:
      - "latest"
    binwiederhier/ntfy:
      - "latest"
    gethomepage/homepage:
      - "latest"
    # Auth
    authelia/authelia:
      - "latest"
    # vaultwarden/server omitted: skopeo strips namespace → "server:latest" (too generic)
    # Use: skopeo copy docker://vaultwarden/server:latest docker://registry.lab.hartr.net/vaultwarden/server:latest
    wallabag/wallabag:
      - "latest"
    # Development
    gitea/gitea:
      - "latest-rootless"
    woodpeckerci/woodpecker-server:
      - "latest"
    woodpeckerci/woodpecker-agent:
      - "latest"
    codercom/code-server:
      - "latest"
    gollumwiki/gollum:
      - "latest"
    corentinth/it-tools:
      - "latest"
    # Media
    freshrss/freshrss:
      - "latest"
    linuxserver/calibre-web:
      - "latest"
    syncthing/syncthing:
      - "latest"
    zadam/trilium:
      - "latest"
    jgraph/drawio:
      - "latest"
    # Monitoring
    amir20/dozzle:
      - "latest"
    netdata/netdata:
      - "latest"
    louislam/uptime-kuma:
      - "2.0.2"

lscr.io:
  images:
    linuxserver/bookstack:
      - "latest"
    linuxserver/speedtest-tracker:
      - "latest"

ghcr.io:
  images:
    linkwarden/linkwarden:
      - "latest"
    paperless-ngx/paperless-ngx:
      - "latest"
    advplyr/audiobookshelf:
      - "latest"

mcr.microsoft.com:
  images:
    playwright:
      - "v1.50.0-noble"

gcr.io:
  images:
    cadvisor/cadvisor:
      - "v0.47.0"

quay.io:
  images:
    skopeo/stable:
      - "latest"

codeberg.org:
  images:
    readeck/readeck:
      - "latest"
EOH
      }

      resources {
        cpu    = 500
        memory = 512
      }
    }
  }
}
