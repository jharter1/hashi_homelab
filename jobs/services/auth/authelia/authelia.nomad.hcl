job "authelia" {
  datacenters = ["dc1"]
  type        = "service"

  group "authelia" {
    count = 1

    network {
      mode = "host"
      port "http" {
        static = 9091
      }
    }

    volume "authelia_data" {
      type      = "host"
      read_only = false
      source    = "authelia_data"
    }

    task "authelia" {
      driver = "docker"

      # Enable Vault workload identity for secrets access
      vault {
        policies = ["nomad-workloads"]
      }

      config {
        image        = "authelia/authelia:latest"
        network_mode = "host"
        ports        = ["http"]
        privileged   = true

        volumes = [
          "local/configuration.yml:/config/configuration.yml",
          "local/users_database.yml:/config/users_database.yml",
        ]
      }

      volume_mount {
        volume      = "authelia_data"
        destination = "/data"
      }

      # Main Authelia configuration with Vault-backed secrets
      template {
        destination = "local/configuration.yml"
        data        = <<EOH
server:
  host: 0.0.0.0
  port: 9091
  path: ""
  read_buffer_size: 4096
  write_buffer_size: 4096

log:
  level: info
  format: text

# Secrets from Vault
jwt_secret: {{ with secret "secret/data/authelia/config" }}{{ .Data.data.jwt_secret }}{{ end }}

authentication_backend:
  password_reset:
    disable: false
  
  # File-based authentication
  file:
    path: /config/users_database.yml
    password:
      algorithm: argon2id
      iterations: 3
      salt_length: 16
      parallelism: 4
      memory: 64

access_control:
  default_policy: deny
  
  rules:
    # Bypass auth for Authelia itself and public services
    - domain:
        - authelia.lab.hartr.net
        - home.lab.hartr.net
        - whoami.lab.hartr.net
      policy: bypass
    
    # Bypass auth for internal monitoring services (needed for Grafana data sources)
    - domain:
        - prometheus.lab.hartr.net
        - loki.lab.hartr.net
      policy: bypass
    
    # Bypass API endpoints that have their own authentication
    # Calibre OPDS API - used by ebook readers
    - domain:
        - calibre.lab.hartr.net
      resources:
        - "^/opds.*$"
      policy: bypass
    
    # Grafana API - used for dashboards, data sources, and integrations
    - domain:
        - grafana.lab.hartr.net
      resources:
        - "^/api/.*$"
        - "^/avatar/.*$"
        - "^/public/.*$"
      policy: bypass
    
    # Protected services - require authentication
    - domain:
        - grafana.lab.hartr.net
        - alertmanager.lab.hartr.net
        - gitea.lab.hartr.net
        - wiki.lab.hartr.net
        - code.lab.hartr.net
        - uptime-kuma.lab.hartr.net
        - calibre.lab.hartr.net
        - audiobookshelf.lab.hartr.net
        - freshrss.lab.hartr.net
        - seafile.lab.hartr.net
        - minio.lab.hartr.net
        - registry-ui.lab.hartr.net
        - traefik.lab.hartr.net
        - speedtest.lab.hartr.net
      policy: one_factor
    
    # Admin-only infrastructure services
    - domain:
        - vault.lab.hartr.net
        - nomad.lab.hartr.net
        - consul.lab.hartr.net
      policy: one_factor
      subject:
        - "group:admins"

session:
  secret: {{ with secret "secret/data/authelia/config" }}{{ .Data.data.session_secret }}{{ end }}
  
  cookies:
    - domain: .lab.hartr.net
      authelia_url: https://authelia.lab.hartr.net
      default_redirection_url: https://home.lab.hartr.net
      name: authelia_session
      expiration: 12h
      inactivity: 1h
      remember_me: 1M
  
  # Use Redis for session storage (better than in-memory)
  redis:
    host: {{ range service "redis" }}{{ .Address }}{{ end }}
    port: 6379

regulation:
  max_retries: 5
  find_time: 2m
  ban_time: 10m

storage:
  encryption_key: {{ with secret "secret/data/authelia/config" }}{{ .Data.data.encryption_key }}{{ end }}
  
  # PostgreSQL backend (shared with other services)
  postgres:
    address: tcp://{{ range service "postgresql" }}{{ .Address }}{{ end }}:5432
    database: authelia
    schema: public
    username: authelia
    password: {{ with secret "secret/data/postgres/authelia" }}{{ .Data.data.password }}{{ end }}
    timeout: 5s

notifier:
  disable_startup_check: false
  filesystem:
    filename: /data/notification.txt

# Optional: Enable SMTP for real email notifications
# notifier:
#   smtp:
#     host: smtp.gmail.com
#     port: 587
#     username: your-email@gmail.com
#     password: your-app-password
#     sender: Authelia <authelia@lab.hartr.net>
EOH
      }

      # User database - update the password hash after running generate-authelia-password.fish
      template {
        destination = "local/users_database.yml"
        data        = <<EOH
---
# Authelia User Database
# Generate password hash with: ./scripts/generate-authelia-password.fish

users:
  jack:
    displayname: "Jack Harter"
    # TODO: Replace with actual hash from generate-authelia-password.fish
    password: "$argon2id$v=19$m=65536,t=3,p=4$3ixvZLI5S3TJ3v9+CBawbA$vJ5tv88X2oPrddVHwFEqDGVvt08+xNsHTHLrODgUjcc"
    email: jack@hartr.net
    groups:
      - admins
      - users

# Add more users as needed:
# username:
#   displayname: "Full Name"
#   password: "$argon2id$..."
#   email: email@example.com
#   groups:
#     - users
EOH
      }

      resources {
        cpu    = 200
        memory = 256
      }

      service {
        name = "authelia"
        port = "http"
        tags = [
          "security",
          "authentication",
          "sso",
          "traefik.enable=true",
          "traefik.http.routers.authelia.rule=Host(`authelia.lab.hartr.net`)",
          "traefik.http.routers.authelia.entrypoints=websecure",
          "traefik.http.routers.authelia.tls=true",
          "traefik.http.routers.authelia.tls.certresolver=letsencrypt",
          # Define the ForwardAuth middleware for other services
          "traefik.http.middlewares.authelia.forwardauth.address=http://authelia.service.consul:9091/api/verify?rd=https://authelia.lab.hartr.net",
          "traefik.http.middlewares.authelia.forwardauth.trustForwardHeader=true",
          "traefik.http.middlewares.authelia.forwardauth.authResponseHeaders=Remote-User,Remote-Groups,Remote-Name,Remote-Email",
        ]
        check {
          type     = "http"
          path     = "/api/health"
          interval = "10s"
          timeout  = "5s"
          
          check_restart {
            limit           = 3
            grace           = "30s"
            ignore_warnings = false
          }
        }
      }
    }
  }
}


