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

      config {
        image        = "authelia/authelia:latest"
        network_mode = "host"
        ports        = ["http"]

        volumes = [
          "local/configuration.yml:/config/configuration.yml:ro",
        ]
      }

      volume_mount {
        volume      = "authelia_data"
        destination = "/data"
      }

      template {
        destination = "local/configuration.yml"
        data        = <<EOH
server:
  host: 0.0.0.0
  port: 9091
  path: ""

log:
  level: info

jwt_secret: CHANGE_ME_GENERATE_RANDOM_STRING
default_redirection_url: http://home.home

authentication_backend:
  file:
    path: /data/users.yml
    password:
      algorithm: argon2id
      iterations: 1
      salt_length: 16
      parallelism: 8
      memory: 64

access_control:
  default_policy: deny
  rules:
    - domain: "*.home"
      policy: one_factor

session:
  name: authelia_session
  secret: CHANGE_ME_GENERATE_RANDOM_STRING
  expiration: 1h
  inactivity: 5m
  remember_me_duration: 1M
  domain: home

regulation:
  max_retries: 3
  find_time: 2m
  ban_time: 5m

storage:
  local:
    path: /data/db.sqlite3

notifier:
  filesystem:
    filename: /data/notification.txt
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
          "traefik.http.routers.authelia.rule=Host(`authelia.home`)",
          "traefik.http.routers.authelia.entrypoints=websecure",
          "traefik.http.routers.authelia.tls=true",
          # Note: HTTPS certificate configuration needed (see plan for Vault PKI setup)
        ]
        check {
          type     = "http"
          path     = "/api/verify"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}

