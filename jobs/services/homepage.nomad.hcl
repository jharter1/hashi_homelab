job "homepage" {
  datacenters = ["dc1"]
  type        = "service"

  group "homepage" {
    count = 1

    network {
      mode = "host"
      port "http" {
        static = 3333
      }
    }

    restart {
      attempts = 3
      delay    = "30s"
      interval = "5m"
      mode     = "fail"
    }

    update {
      max_parallel     = 1
      health_check     = "checks"
      min_healthy_time = "10s"
      healthy_deadline = "5m"
      auto_revert      = true
    }

    task "homepage" {
      driver = "docker"

      # Homepage configuration files
      template {
        destination = "local/config/settings.yaml"
        data = <<EOH
---
title: Homelab Dashboard
favicon: https://cdn.jsdelivr.net/gh/walkxcode/dashboard-icons/png/nomad.png
theme: dark
color: slate
headerStyle: boxed
layout:
  Infrastructure:
    style: row
    columns: 3
  Monitoring:
    style: row
    columns: 3
  Services:
    style: row
    columns: 4
EOH
      }

      template {
        destination = "local/config/services.yaml"
        data = <<EOH
---
- Infrastructure:
    - Nomad:
        icon: nomad.png
        href: http://10.0.0.50:4646
        description: Container Orchestration
    - Consul:
        icon: consul.png
        href: http://10.0.0.50:8500
        description: Service Discovery
    - Vault:
        icon: vault.png
        href: http://10.0.0.30:8200
        description: Secrets Management
    - Traefik:
        icon: traefik.png
        href: http://traefik.home
        description: Reverse Proxy
        widget:
          type: traefik
          url: http://10.0.0.60:8080

- Monitoring:
    - Grafana:
        icon: grafana.png
        href: http://grafana.home
        description: Metrics Visualization
    - Alertmanager:
        icon: prometheus.png
        href: http://alertmanager.home
        description: Alert Routing
    - Loki:
        icon: loki.png
        href: http://loki.home
        description: Log Aggregation
    - Netdata:
        icon: netdata.png
        href: http://netdata.home
        description: Real-time Performance
    - Dozzle:
        icon: dozzle.png
        href: http://dozzle.home
        description: Docker Log Viewer
    - Prometheus:
        icon: prometheus.png
        href: http://prometheus.home
        description: Metrics Collection
        widget:
          type: prometheus
          url: http://prometheus.home

- Services:
    - Docker Registry:
        icon: docker.png
        href: http://registry-ui.home
        description: Container Registry
    - Jenkins:
        icon: jenkins.png
        href: http://jenkins.home
        description: CI/CD
    - Gitea:
        icon: gitea.png
        href: http://gitea.home
        description: Self-hosted Git
    - Code Server:
        icon: code.png
        href: http://codeserver.home
        description: VS Code in Browser
    - Nextcloud:
        icon: nextcloud.png
        href: http://nextcloud.home
        description: File Sync & Share
    - Calibre Web:
        icon: calibre-web.png
        href: http://calibre.home
        description: eBook Library
        widget:
          type: calibreweb
          url: http://calibre.home
    - Uptime Kuma:
        icon: uptime-kuma.png
        href: http://uptime-kuma.home
        description: Uptime Monitoring
        widget:
          type: uptimekuma
          url: http://uptime-kuma.home
          slug: default

- Security:
    - Vaultwarden:
        icon: vaultwarden.png
        href: http://vaultwarden.home
        description: Password Manager
    - Authelia:
        icon: authelia.png
        href: http://authelia.home
        description: SSO & Authentication
EOH
      }

      template {
        destination = "local/config/widgets.yaml"
        data = <<EOH
---
- resources:
    cpu: true
    memory: true
    disk: /
    
- search:
    provider: google
    target: _blank

- datetime:
    text_size: xl
    format:
      timeStyle: short
      dateStyle: short
EOH
      }

      template {
        destination = "local/config/bookmarks.yaml"
        data = <<EOH
---
- Documentation:
    - GitHub:
        - icon: github.png
          href: https://github.com/jharter1/hashi_homelab
    - Nomad Docs:
        - icon: nomad.png
          href: https://developer.hashicorp.com/nomad/docs
    - Consul Docs:
        - icon: consul.png
          href: https://developer.hashicorp.com/consul/docs
EOH
      }

      env {
        HOMEPAGE_VAR_TITLE     = "Homelab Dashboard"
        LOG_LEVEL              = "info"
        HOSTNAME               = "0.0.0.0"
        PORT                   = "3333"
        HOMEPAGE_ALLOWED_HOSTS = "home.home"
        NODE_OPTIONS           = "--dns-result-order=ipv4first"
      }

      config {
        image    = "gethomepage/homepage:latest"
        network_mode = "host"
                # Use Pi-hole for DNS resolution
        dns_servers = ["10.0.0.10", "1.1.1.1"]
                # Mount local config files into container
        volumes = [
          "local/config:/app/config"
        ]
      }

      resources {
        cpu    = 200
        memory = 256
      }

      service {
        name = "homepage"
        port = "http"

        tags = [
          "traefik.enable=true",
          "traefik.http.routers.homepage.rule=Host(`home.home`)",
          "traefik.http.routers.homepage.entrypoints=web",
        ]

        check {
          type     = "http"
          path     = "/"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}
