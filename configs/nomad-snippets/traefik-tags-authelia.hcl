# Traefik Tags: Authelia Protected Service
# For services that should be behind Authelia SSO
# Replace SERVICE with your service name

tags = [
  "traefik.enable=true",
  "traefik.http.routers.SERVICE.rule=Host(`SERVICE.lab.hartr.net`)",
  "traefik.http.routers.SERVICE.entrypoints=websecure",
  "traefik.http.routers.SERVICE.tls=true",
  "traefik.http.routers.SERVICE.tls.certresolver=letsencrypt",
  "traefik.http.routers.SERVICE.middlewares=authelia@file"
]
