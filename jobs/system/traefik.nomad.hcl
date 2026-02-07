job "traefik" {
  datacenters = ["dc1"]
  type        = "system" # Run on every client node

  group "traefik" {
    # Add volume for certificate storage
    volume "traefik_acme" {
      type      = "host"
      source    = "traefik_acme"
      read_only = false
    }

    network {
      port "http" {
        static = 80
      }
      port "https" {
        static = 443
      }
      port "admin" {
        static = 8080
      }
    }

    service {
      name = "traefik"
      port = "admin"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.dashboard.rule=Host(`traefik.lab.hartr.net`)",
        "traefik.http.routers.dashboard.service=api@internal",
        "traefik.http.routers.dashboard.entrypoints=websecure",
        "traefik.http.routers.dashboard.tls=true",
        "traefik.http.routers.dashboard.tls.certresolver=letsencrypt",
      ]

      check {
        name     = "alive"
        type     = "tcp"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "traefik" {
      driver = "docker"

      config {
        image        = "traefik:v3.0"
        network_mode = "host"

        volumes = [
          "local/traefik.yml:/etc/traefik/traefik.yml",
          "local/dynamic.yml:/etc/traefik/dynamic.yml",
        ]
      }

      # Mount the certificate storage volume
      volume_mount {
        volume      = "traefik_acme"
        destination = "/letsencrypt"
        read_only   = false
      }

      # Load AWS credentials from Nomad variables
      template {
        data = <<EOF
AWS_ACCESS_KEY_ID={{ with nomadVar "nomad/jobs/traefik" }}{{ .aws_access_key }}{{ end }}
AWS_SECRET_ACCESS_KEY={{ with nomadVar "nomad/jobs/traefik" }}{{ .aws_secret_key }}{{ end }}
AWS_REGION=us-east-1
AWS_HOSTED_ZONE_ID={{ with nomadVar "nomad/jobs/traefik" }}{{ .aws_hosted_zone_id }}{{ end }}
EOF
        destination = "secrets/aws.env"
        env         = true
      }

      # Traefik static configuration
      template {
        data = <<EOF
# Traefik Static Configuration
# See: https://doc.traefik.io/traefik/

api:
  dashboard: true
  insecure: true

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
          permanent: true

  websecure:
    address: ":443"

providers:
  consulCatalog:
    prefix: traefik
    exposedByDefault: false
    endpoint:
      address: 127.0.0.1:8500
      scheme: http
  
  file:
    filename: /etc/traefik/dynamic.yml
    watch: true

certificatesResolvers:
  letsencrypt:
    acme:
      email: jack@hartr.net
      storage: /letsencrypt/acme.json
      dnsChallenge:
        provider: route53
        resolvers:
          - "1.1.1.1:53"
          - "8.8.8.8:53"
        delayBeforeCheck: 30s
      # IMPORTANT: Uncomment for testing to avoid rate limits
      # caServer: https://acme-staging-v02.api.letsencrypt.org/directory

log:
  level: INFO

accessLog:
  filePath: /dev/stdout
EOF
        destination = "local/traefik.yml"
      }

      # Dynamic configuration for Authelia ForwardAuth middleware
      template {
        data = <<EOF
# Traefik Dynamic Configuration
http:
  middlewares:
    authelia:
      forwardAuth:
        address: http://{{ range service "authelia" }}{{ .Address }}{{ end }}:9091/api/authz/forward-auth
        trustForwardHeader: true
        authResponseHeaders:
          - Remote-User
          - Remote-Groups
          - Remote-Email
          - Remote-Name
EOF
        destination = "local/dynamic.yml"
      }

      resources {
        cpu    = 200
        memory = 256
      }
    }
  }
}
