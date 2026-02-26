job "traefik" {
  datacenters = ["dc1"]
  type        = "service"

  group "traefik" {
    count = 1

    # Pin to client-1 so DNS (*.lab.hartr.net → 10.0.0.60) always resolves correctly
    constraint {
      attribute = "${node.unique.name}"
      value     = "dev-nomad-client-1"
    }

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
        
        # Run as root to bind to privileged ports 80/443
        privileged = true

        volumes = [
          # Static config from external file
          "/mnt/nas/configs/infrastructure/traefik/traefik.yml:/etc/traefik/traefik.yml:ro",
          # Dynamic config from template (needs Consul SD)
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

      # NOTE: Static config now loaded from /mnt/nas/configs/infrastructure/traefik/traefik.yml
      # This eliminates the HEREDOC pattern and centralizes configuration

      # Dynamic configuration for Authelia ForwardAuth middleware
      template {
        data = <<EOF
# Traefik Dynamic Configuration
http:
  middlewares:
    authelia:
      forwardAuth:
        address: http://{{ range service "authelia" }}{{ .Address }}{{ end }}:9091/api/verify?rd=https://authelia.lab.hartr.net
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
        cpu        = 200
        memory     = 64
        memory_max = 256
      }
    }
  }
}
