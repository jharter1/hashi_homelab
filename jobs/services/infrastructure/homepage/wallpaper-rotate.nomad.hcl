job "wallpaper-rotate" {
  datacenters = ["dc1"]
  type        = "batch"

  # Rotate wallpaper every morning at 8 AM Chicago time.
  # Force an immediate rotation with:
  #   nomad job periodic force wallpaper-rotate
  #
  # Prerequisites:
  #   - MinIO bucket "wallpapers" must have anonymous readonly access set
  #   - Wallpaper images uploaded to the bucket
  periodic {
    crons            = ["0 8 * * *"]
    prohibit_overlap = true
    time_zone        = "America/Chicago"
  }

  group "rotate" {
    count = 1

    network {
      mode = "host"
    }

    restart {
      attempts = 1
      delay    = "15s"
      interval = "5m"
      mode     = "fail"
    }

    task "rotate" {
      driver = "docker"

      # No Vault needed — bucket is public-read, listing works without credentials.
      template {
        destination = "local/rotate.sh"
        perms       = "0755"
        data        = <<EOH
#!/bin/sh
set -e

# MinIO address resolved via Consul template at job dispatch time
MINIO_URL="{{ range service "minio-api" }}http://{{ .Address }}:{{ .Port }}{{ end }}"

# List objects from the public-read wallpapers bucket via S3 API
wget -O- "$${MINIO_URL}/wallpapers?list-type=2" 2>/dev/null \
  | grep -o '<Key>[^<]*</Key>' \
  | sed 's/<[^>]*>//g' \
  > /tmp/wallpapers.txt

TOTAL=$(wc -l < /tmp/wallpapers.txt | tr -d ' ')
if [ "$TOTAL" -eq 0 ]; then
  echo "No wallpapers found in bucket — skipping"
  exit 0
fi

IDX=$(awk -v n="$TOTAL" -v seed="$(date +%s)" 'BEGIN { srand(seed); print int(rand()*n)+1 }')
WALLPAPER=$(sed -n "$${IDX}p" /tmp/wallpapers.txt)

echo "Rotating to: $WALLPAPER ($IDX/$TOTAL)"
sed -i "s|  image: .*|  image: https://s3.lab.hartr.net/wallpapers/$WALLPAPER|" /homepage/settings.yaml
echo "Done"
EOH
      }

      config {
        image        = "alpine:3"
        network_mode = "host"
        dns_servers  = ["10.0.0.10", "1.1.1.1"]
        command      = "/bin/sh"
        args         = ["/local/rotate.sh"]

        mount {
          type   = "bind"
          source = "/mnt/nas/homepage"
          target = "/homepage"
        }
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }
  }
}
