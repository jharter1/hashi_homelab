job "alertmanager" {
  datacenters = ["dc1"]
  type        = "service"
  priority    = 70

  group "alertmanager" {
    count = 1

    network {
      mode = "host"
      port "http" {
        static = 9093
      }
    }

    volume "alertmanager_data" {
      type      = "host"
      read_only = false
      source    = "alertmanager_data"
    }

    task "alertmanager" {
      driver = "docker"

      config {
        image        = "prom/alertmanager:latest"
        network_mode = "host"
        ports        = ["http"]

        args = [
          "--config.file=/etc/alertmanager/alertmanager.yml",
          "--storage.path=/alertmanager",
          "--web.listen-address=:9093",
        ]

        volumes = [
          "local/alertmanager.yml:/etc/alertmanager/alertmanager.yml",
        ]
      }

      volume_mount {
        volume      = "alertmanager_data"
        destination = "/alertmanager"
      }

      template {
        destination = "local/alertmanager.yml"
        data        = <<EOH
global:
  resolve_timeout: 5m

# Route alerts based on labels
route:
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h
  receiver: 'default'
  routes:
    - match:
        severity: critical
      receiver: 'critical'
    - match:
        severity: warning
      receiver: 'warning'

# Receivers define where alerts are sent
receivers:
  - name: 'default'
    # For now, just log alerts
    # Can be extended with email, Slack, Discord, etc.
    
  - name: 'critical'
    # Critical alerts receiver
    # Add notification channels here (email, Slack, etc.)
    
  - name: 'warning'
    # Warning alerts receiver
    # Add notification channels here

# Inhibit rules to reduce noise
inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'cluster', 'service']
EOH
      }

      resources {
        cpu    = 200
        memory = 256
      }

      service {
        name         = "alertmanager"
        port         = "http"
        address_mode = "host"

        check {
          type     = "http"
          path     = "/-/healthy"
          interval = "10s"
          timeout  = "2s"
          port     = "http"
        }

        tags = [
          "monitoring",
          "alertmanager",
          "traefik.enable=true",
          "traefik.http.routers.alertmanager.rule=Host(`alertmanager.lab.hartr.net`)",
          "traefik.http.routers.alertmanager.entrypoints=websecure",
          "traefik.http.routers.alertmanager.tls=true",
          "traefik.http.routers.alertmanager.tls.certresolver=letsencrypt",
          "traefik.http.routers.alertmanager.middlewares=authelia@file",
        ]
      }
    }
  }
}

