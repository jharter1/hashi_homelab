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
      min_healthy_time = "5s"
      healthy_deadline = "30s"
      progress_deadline = "1m"
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
logo: https://cdn.jsdelivr.net/gh/walkxcode/dashboard-icons/png/home-assistant.png
background:
  image: https://images.unsplash.com/photo-1558618666-fcd25c85cd64?w=1920
  blur: sm
  saturate: 50
  brightness: 50
  opacity: 20

theme: dark
color: slate
headerStyle: boxed
layout:
  Infrastructure:
    style: row
    columns: 3
    icon: mdi-server-network
  Monitoring:
    style: row
    columns: 3
    icon: mdi-chart-line
  Services:
    style: row
    columns: 4
    icon: mdi-apps
  Storage:
    style: row
    columns: 2
    icon: mdi-database
  Security:
    style: row
    columns: 2
    icon: mdi-shield-lock

# Quick launch with keyboard shortcuts
quicklaunch:
  searchDescriptions: true
  hideInternetSearch: false
  hideVisitURL: false

# Custom CSS for additional styling
customCss: |
  .service-card {
    transition: transform 0.2s;
  }
  .service-card:hover {
    transform: scale(1.05);
  }

# Status style
statusStyle: "dot"

# Show stats
showStats: true
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
        href: https://traefik.lab.hartr.net
        description: Reverse Proxy
        widget:
          type: traefik
          url: http://10.0.0.60:8080

- Monitoring:
    - Grafana:
        icon: grafana.png
        href: https://grafana.lab.hartr.net
        description: Metrics Visualization
    - Alertmanager:
        icon: alertmanager.png
        href: https://alertmanager.lab.hartr.net
        description: Alert Routing
    - Loki:
        icon: loki.png
        href: https://loki.lab.hartr.net
        description: Log Aggregation
    - Netdata:
        icon: netdata.png
        href: https://netdata.lab.hartr.net
        description: Real-time Performance
    - Dozzle:
        icon: dozzle.png
        href: https://dozzle.lab.hartr.net
        description: Docker Log Viewer
    - Prometheus:
        icon: prometheus.png
        href: https://prometheus.lab.hartr.net
        description: Metrics Collection
        widget:
          type: prometheus
          url: https://prometheus.lab.hartr.net

- Services:
    - Docker Registry:
        icon: docker.png
        href: https://registry-ui.lab.hartr.net
        description: Container Registry
    - Jenkins:
        icon: jenkins.png
        href: https://jenkins.lab.hartr.net
        description: CI/CD
    - Gitea:
        icon: gitea.png
        href: https://gitea.lab.hartr.net
        description: Self-hosted Git
    - Code Server:
        icon: code.png
        href: https://code.lab.hartr.net
        description: VS Code in Browser
    - Gollum Wiki:
        icon: gollum.png
        href: https://wiki.lab.hartr.net
        description: Git-backed Wiki
    - Nextcloud:
        icon: nextcloud.png
        href: https://nextcloud.lab.hartr.net
        description: File Sync & Share
    - Calibre Web:
        icon: calibre-web.png
        href: https://calibre.lab.hartr.net
        description: eBook Library
        widget:
          type: calibreweb
          url: https://calibre.lab.hartr.net
    - Audiobookshelf:
        icon: audiobookshelf.png
        href: https://audiobookshelf.lab.hartr.net
        description: Audiobook & Podcast Server
        ping: http://10.0.0.60:13378
    - Uptime Kuma:
        icon: uptime-kuma.png
        href: https://uptime-kuma.lab.hartr.net
        description: Uptime Monitoring
        widget:
          type: uptimekuma
          url: https://uptime-kuma.lab.hartr.net
          slug: default
    - Speedtest:
        icon: https://cdn.jsdelivr.net/gh/walkxcode/dashboard-icons/png/speedtest-tracker.png
        href: https://speedtest.lab.hartr.net
        description: Internet Speed Testing


- Storage:
    - MinIO S3:
        icon: minio.png
        href: https://s3.lab.hartr.net
        description: S3-Compatible Object Storage (API)
        ping: http://10.0.0.61:9000
    - MinIO Console:
        icon: minio.png
        href: https://minio.lab.hartr.net
        description: MinIO Admin Console
        ping: http://10.0.0.61:9001
    - NFS Storage:
        icon: mdi-F08F3.png
        href: nfs://10.0.0.220/mnt/storage
        description: Network File System (10.0.0.220)
        ping: 10.0.0.220

- Security:
    - Vaultwarden:
        icon: vaultwarden.png
        href: https://vaultwarden.lab.hartr.net
        description: Password Manager
        ping: http://10.0.0.60:80
    - Authelia:
        icon: authelia.png
        href: https://authelia.lab.hartr.net
        description: SSO & Authentication
        ping: http://10.0.0.60:9091
EOH
      }

      template {
        destination = "local/config/widgets.yaml"
        data = <<EOH
---
# System resources from Glances
- resources:
    label: Homepage Container
    cpu: true
    memory: true
    disk: /
    cputemp: true
    uptime: true

# Weather widget
- openweathermap:
    label: Local Weather
    latitude: 41.8781
    longitude: -87.6298
    units: imperial
    provider: openweathermap
    apiKey: 8cff25cca0e4cf3dcf9aca5b8ca3f378
    cache: 5

# Search functionality
- search:
    provider: google
    target: _blank
    focus: true
    showSearchSuggestions: true

# Date and time
- datetime:
    text_size: xl
    format:
      timeStyle: short
      dateStyle: short
      hour12: true

# Greeting based on time of day
- greeting:
    text_size: xl
    text: "Welcome to your Homelab!"
EOH
      }

      template {
        destination = "local/config/docker.yaml"
        data = <<EOH
---
# Docker integration disabled - not available in rootless setup
# Uncomment below if Docker TCP API is enabled on port 2375
# my-docker:
#   host: 10.0.0.60
#   port: 2375
EOH
      }

      template {
        destination = "local/config/custom.css"
        data = <<EOH
/* Custom styling for Homepage dashboard */
.service-card {
  transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
  border-radius: 12px;
}

.service-card:hover {
  transform: translateY(-4px);
  box-shadow: 0 12px 24px rgba(0, 0, 0, 0.4);
}

.service-title {
  font-weight: 600;
  letter-spacing: 0.5px;
}

.widget {
  backdrop-filter: blur(10px);
  background: rgba(30, 41, 59, 0.6);
  border: 1px solid rgba(148, 163, 184, 0.1);
}

/* Pulse animation for status indicators */
@keyframes pulse {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.5; }
}

.status-dot {
  animation: pulse 2s cubic-bezier(0.4, 0, 0.6, 1) infinite;
}

/* Smooth scrolling */
html {
  scroll-behavior: smooth;
}

/* Card hover glow effect */
.service-card:hover {
  box-shadow: 0 0 20px rgba(56, 189, 248, 0.3);
}
EOH
      }

      template {
        destination = "local/config/bookmarks.yaml"
        data = <<EOH
---
- Documentation:
    - Homelab GitHub:
        - icon: github.png
          href: https://github.com/jharter1/hashi_homelab
          description: Main repository
    - Nomad Docs:
        - icon: nomad.png
          href: https://developer.hashicorp.com/nomad/docs
          description: Job orchestration
    - Consul Docs:
        - icon: consul.png
          href: https://developer.hashicorp.com/consul/docs
          description: Service mesh & discovery
    - Vault Docs:
        - icon: vault.png
          href: https://developer.hashicorp.com/vault/docs
          description: Secrets management
    - Traefik Docs:
        - icon: traefik.png
          href: https://doc.traefik.io/traefik/
          description: Reverse proxy

- Quick Links:
    - Nomad UI:
        - icon: nomad.png
          href: http://10.0.0.50:4646
          description: Job management
    - Consul UI:
        - icon: consul.png
          href: http://10.0.0.50:8500
          description: Service catalog
    - Traefik Dashboard:
        - icon: traefik.png
          href: http://10.0.0.60:8080
          description: Routing dashboard
    - Prometheus:
        - icon: prometheus.png
          href: https://prometheus.lab.hartr.net
          description: Metrics & alerts
    - Grafana:
        - icon: grafana.png
          href: https://grafana.lab.hartr.net
          description: Dashboards

- Homelab Resources:
    - r/homelab:
        - icon: reddit.png
          href: https://reddit.com/r/homelab
          description: Homelab community
    - r/selfhosted:
        - icon: reddit.png
          href: https://reddit.com/r/selfhosted
          description: Self-hosting community
    - Awesome Selfhosted:
        - icon: github.png
          href: https://github.com/awesome-selfhosted/awesome-selfhosted
          description: Service directory
    - LinuxServer.io:
        - icon: linuxserver.png
          href: https://www.linuxserver.io/
          description: Container images

- Monitoring:
    - Netdata:
        - icon: netdata.png
          href: https://netdata.lab.hartr.net
          description: Real-time metrics
    - Dozzle:
        - icon: dozzle.png
          href: https://dozzle.lab.hartr.net
          description: Container logs
    - Uptime Kuma:
        - icon: uptime-kuma.png
          href: https://uptime-kuma.lab.hartr.net
          description: Uptime monitoring
EOH
      }

      env {
        HOMEPAGE_VAR_TITLE     = "Homelab Dashboard"
        LOG_LEVEL              = "info"
        HOSTNAME               = "0.0.0.0"
        PORT                   = "3333"
        HOMEPAGE_ALLOWED_HOSTS = "home.lab.hartr.net"
        NODE_OPTIONS           = "--dns-result-order=ipv4first"
      }

      config {
        image    = "gethomepage/homepage:latest"
        network_mode = "host"
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
          "traefik.http.routers.homepage.rule=Host(`home.lab.hartr.net`)",
          "traefik.http.routers.homepage.entrypoints=websecure",
          "traefik.http.routers.homepage.tls=true",
          "traefik.http.routers.homepage.tls.certresolver=letsencrypt",
        ]

        check {
          type     = "http"
          path     = "/"
          interval = "5s"
          timeout  = "2s"
        }
      }
    }
  }
}
