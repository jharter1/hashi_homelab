job "docker-registry" {
  datacenters = ["dc1"]
  type        = "service"

  group "registry" {
    count = 1

    network {
      mode = "host"
      port "http" {
        static = 5000
      }
      port "ui" {
        static = 5001
      }
    }

    volume "registry_data" {
      type      = "host"
      read_only = false
      source    = "registry_data"
    }

    task "registry" {
      driver = "docker"

      config {
        image        = "registry:2"
        network_mode = "host"
        ports        = ["http"]
      }

      volume_mount {
        volume      = "registry_data"
        destination = "/var/lib/registry"
      }

      # Configuration for pull-through cache
      template {
        destination = "local/config.yml"
        data        = <<EOH
version: 0.1
log:
  fields:
    service: registry
storage:
  cache:
    blobdescriptor: inmemory
  filesystem:
    rootdirectory: /var/lib/registry
  delete:
    enabled: true
http:
  addr: :5000
  headers:
    X-Content-Type-Options: [nosniff]
    Access-Control-Allow-Origin: ['*']
    Access-Control-Allow-Methods: ['HEAD', 'GET', 'OPTIONS', 'DELETE']
    Access-Control-Allow-Headers: ['Authorization', 'Accept', 'Content-Type']
    Access-Control-Expose-Headers: ['Docker-Content-Digest']
health:
  storagedriver:
    enabled: true
    interval: 10s
    threshold: 3
# Pull-through cache configuration for Docker Hub
proxy:
  remoteurl: https://registry-1.docker.io
  username: ""
  password: ""
EOH
      }

      env {
        REGISTRY_HTTP_ADDR = "0.0.0.0:5000"
      }

      resources {
        cpu    = 500
        memory = 512
      }

      service {
        name = "docker-registry"
        port = "http"
        tags = [
          "registry",
          "docker",
          "traefik.enable=true",
          "traefik.http.routers.registry.rule=Host(`registry.home`)",
          # CORS middleware for registry UI
          "traefik.http.middlewares.registry-cors.headers.accesscontrolallowmethods=GET,HEAD,OPTIONS,DELETE",
          "traefik.http.middlewares.registry-cors.headers.accesscontrolalloworiginlist=http://registry-ui.home,http://10.0.0.60:5001",
          "traefik.http.middlewares.registry-cors.headers.accesscontrolallowheaders=Authorization,Accept,Content-Type",
          "traefik.http.middlewares.registry-cors.headers.accesscontrolexposeheaders=Docker-Content-Digest",
          # Allow larger uploads for Docker images
          "traefik.http.middlewares.registry-buffering.buffering.maxRequestBodyBytes=2147483648",
          "traefik.http.routers.registry.middlewares=registry-cors,registry-buffering",
        ]
        check {
          type     = "http"
          path     = "/"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }

    # Optional: Add a simple web UI for the registry
    task "registry-ui" {
      driver = "docker"

      config {
        image        = "joxit/docker-registry-ui:latest"
        network_mode = "host"
        ports        = ["ui"]
      }

      env {
        REGISTRY_TITLE       = "Homelab Docker Registry"
        REGISTRY_URL         = "http://registry.home"
        DELETE_IMAGES        = "true"
        SHOW_CONTENT_DIGEST  = "true"
        SINGLE_REGISTRY      = "true"
        NGINX_PROXY_PASS_URL = "http://registry.home"
        NGINX_LISTEN_PORT    = "5001"
        CORS_ALLOWED_ORIGINS = "*"
      }

      resources {
        cpu    = 200
        memory = 128
      }

      service {
        name = "registry-ui"
        port = "ui"
        tags = [
          "registry",
          "ui",
          "traefik.enable=true",
          "traefik.http.routers.registry-ui.rule=Host(`registry-ui.home`)",
        ]
        check {
          type     = "tcp"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}
