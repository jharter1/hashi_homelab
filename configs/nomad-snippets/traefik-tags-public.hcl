# Traefik Tags: Public Service (No Auth)
# For publicly accessible services like monitoring stack
# Replace SERVICE with your service name

tags = [
  "traefik.enable=true",
  "traefik.http.routers.SERVICE.rule=Host(`SERVICE.home`)",
  "traefik.http.routers.SERVICE.entrypoints=websecure",
  "traefik.http.routers.SERVICE.tls=true",
  "traefik.http.routers.SERVICE.tls.certresolver=letsencrypt"
]
