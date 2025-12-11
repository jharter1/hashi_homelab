job "traefik" {
  datacenters = ["dc1"]
  type        = "system" # Run on every client node

  group "traefik" {
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

    # Vault integration for workload identity
    vault {
      cluster  = "default"
      policies = ["access-secrets"]
    }

    service {
      name = "traefik-dashboard"
      port = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.dashboard.rule=Host(`traefik.home`)",
        "traefik.http.routers.dashboard.service=api@internal",
        "traefik.http.routers.dashboard.entrypoints=websecure",
        "traefik.http.routers.dashboard.tls=true",
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
        image        = "traefik:v2.10"
        network_mode = "host"

        volumes = [
          "local:/certs"
        ]

        args = [
          "--api.insecure=true",
          "--providers.consulcatalog=true",
          "--providers.consulcatalog.exposedByDefault=false",
          "--providers.consulcatalog.endpoint.address=127.0.0.1:8500",
          "--entrypoints.web.address=:80",
          "--entrypoints.websecure.address=:443",
          "--entrypoints.web.http.redirections.entryPoint.to=websecure",
          "--entrypoints.web.http.redirections.entryPoint.scheme=https",
          "--providers.file.directory=/certs",
          "--providers.file.watch=true",
        ]
      }

      # Issue certificate from Vault PKI - each template call generates a NEW cert
      # so we use change_mode="noop" to prevent restarts
      template {
        data        = "{{ with secret \"pki_int/issue/service\" \"common_name=*.home\" \"alt_names=home\" \"ttl=720h\" }}{{ .Data.certificate }}{{ end }}"
        destination = "local/tls.crt"
        change_mode = "noop"
      }

      template {
        data        = "{{ with secret \"pki_int/issue/service\" \"common_name=*.home\" \"alt_names=home\" \"ttl=720h\" }}{{ .Data.private_key }}{{ end }}"
        destination = "local/tls.key"
        change_mode = "noop"
      }

      template {
        data        = "{{ with secret \"pki_int/issue/service\" \"common_name=*.home\" \"alt_names=home\" \"ttl=720h\" }}{{ range .Data.ca_chain }}{{ . }}\n{{ end }}{{ end }}"
        destination = "local/ca.crt"
        change_mode = "noop"
      }

      # Traefik dynamic TLS configuration
      template {
        data        = <<EOT
[tls.stores]
  [tls.stores.default]
    [tls.stores.default.defaultCertificate]
      certFile = "/certs/tls.crt"
      keyFile  = "/certs/tls.key"

[[tls.certificates]]
  certFile = "/certs/tls.crt"
  keyFile  = "/certs/tls.key"
EOT
        destination = "local/tls-config.toml"
      }
    }
  }
}
