job "image-preloader" {
  datacenters = ["dc1"]
  type        = "system"  # Runs on all client nodes
  priority    = 100       # High priority to run quickly

  update {
    max_parallel      = 10
    health_check      = "task_states"
    min_healthy_time  = "5s"
    healthy_deadline  = "8m"
    progress_deadline = "10m"
  }

  group "preload" {
    count = 1
    # Restart this task periodically to pull latest images
    restart {
      attempts = 2
      interval = "30m"
      delay    = "15s"
      mode     = "delay"
    }

    task "pull-images" {
      driver = "docker"

      config {
        image   = "docker:27-cli"
        command = "sh"
        args = ["-c", <<EOF
set -e
echo "Starting image pre-pull at $(date)"

# System images (run frequently)
echo "Pulling system images..."
docker pull traefik:v2.10 &
docker pull grafana/alloy:latest &
docker pull amir20/dozzle:latest &
docker pull netdata/netdata:latest &

# Service images
echo "Pulling service images..."
docker pull gethomepage/homepage:latest &
docker pull linuxserver/calibre-web:latest &
docker pull jenkins/jenkins:lts &
docker pull louislam/uptime-kuma:2.0.2 &
docker pull minio/minio:RELEASE.2023-09-04T19-57-37Z &
docker pull gitea/gitea:latest &
docker pull gollumwiki/gollum:latest &
docker pull registry:2 &
docker pull joxit/docker-registry-ui:latest &
docker pull grafana/grafana:latest &
docker pull grafana/loki:3.6.0 &
docker pull vaultwarden/server:latest &
docker pull prom/prometheus:latest &
docker pull prom/alertmanager:latest &
docker pull codercom/code-server:latest &
docker pull authelia/authelia:latest &
docker pull traefik/whoami &
docker pull seafileltd/seafile-mc:11.0-latest &
docker pull mariadb:11.2 &
docker pull ghcr.io/advplyr/audiobookshelf:latest &
docker pull postgres:16-alpine &
docker pull freshrss/freshrss:latest &

# Wait for all background pulls to complete
wait

echo "Image pre-pull completed successfully at $(date)"
echo "Sleeping to keep container alive and check for updates periodically..."

# Sleep for 6 hours, then restart to pull latest images
sleep 21600
EOF
        ]

        # Mount Docker socket to pull images
        volumes = [
          "/var/run/docker.sock:/var/run/docker.sock"
        ]
      }

      resources {
        cpu    = 200
        memory = 256
      }

      # Don't fail the whole job if image pull fails
      # (e.g., network issues, registry down)
      restart {
        attempts = 2
        interval = "5m"
        delay    = "30s"
        mode     = "delay"
      }
    }
  }
}
