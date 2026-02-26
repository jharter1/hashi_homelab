job "alloy" {
  datacenters = ["dc1"]
  type        = "system" # Runs on all client nodes

  group "alloy" {
    network {
      mode = "host"
      # The host network mode means the port isn't published via Nomad's networking,
      # but it's still useful for the check and service discovery.
      port "http" {
        static = 12345
      }
    }

    task "alloy" {
      driver = "docker"

      config {
        image        = "grafana/alloy:latest"
        network_mode = "host"
        # The 'ports' list is mainly for the service stanza below when using host network.
        ports = ["http"]

        args = [
          "run",
          "--server.http.listen-addr=0.0.0.0:12345",
          "--storage.path=/alloy/data",
          "--disable-reporting",
          "/alloy/config.alloy",
        ]

        # 1. Mount the necessary host paths for log scraping/discovery
        volumes = [
          "local/config.alloy:/alloy/config.alloy:ro",
          "local/data:/alloy/data",
          # For Docker discovery and log scraping
          "/var/run/docker.sock:/var/run/docker.sock:ro",
          "/var/lib/docker/containers:/var/lib/docker/containers:ro",
          # For journald log scraping
          "/var/log/journal:/var/log/journal:ro",
          "/run/log/journal:/run/log/journal:ro",
          "/etc/machine-id:/etc/machine-id:ro",
        ]
      }

      # 2. The template block that generates the config file
      template {
        # Destination inside the task's allocation directory.
        # Nomad automatically creates a volume named "local" for this directory.
        destination = "local/config.alloy"
        data        = <<EOH
logging {
  level = "info"
}

// Forward traces to Tempo via Consul DNS
otelcol.exporter.otlp "tempo" {
  client {
    endpoint = "tempo.service.consul:4317"
    tls {
      insecure = true
    }
  }
}

// Export Alloy's own internal traces to Tempo (10% sampling)
tracing {
  sampling_fraction = 0.1
  write_to          = [otelcol.exporter.otlp.tempo.input]
}

// Write logs to Loki via Consul service discovery
loki.write "default" {
  endpoint {
    url = "http://{{ range service "loki" }}{{ .Address }}:{{ .Port }}{{ end }}/loki/api/v1/push"
  }
}

// Docker container discovery
discovery.docker "containers" {
  host = "unix:///var/run/docker.sock"
}

// Relabel discovery targets to set stream labels BEFORE log collection.
// loki.source.docker strips __meta_* labels, so labels must be promoted here.
discovery.relabel "docker" {
  targets = discovery.docker.containers.targets

  rule {
    source_labels = ["__meta_docker_container_name"]
    regex         = "/(.*)"
    target_label  = "container"
  }

  rule {
    target_label = "job"
    replacement  = "docker"
  }
}

// Collect Docker container logs using the pre-labeled targets
loki.source.docker "containers" {
  host       = "unix:///var/run/docker.sock"
  targets    = discovery.relabel.docker.output
  forward_to = [loki.write.default.receiver]
}

// Collect systemd journal logs
loki.source.journal "system" {
  path      = "/var/log/journal"
  labels    = { job = "systemd" }
  forward_to = [loki.write.default.receiver]
}
EOH
      }

      resources {
        cpu        = 200
        memory     = 128
        memory_max = 256
      }

      service {
        name = "alloy"
        port = "http"
        tags = [
          "logging",
          "telemetry",
          "traefik.enable=true",
          "traefik.http.routers.alloy.rule=Host(`alloy.lab.hartr.net`)",
          "traefik.http.routers.alloy.entrypoints=websecure",
          "traefik.http.routers.alloy.tls=true",
          "traefik.http.routers.alloy.tls.certresolver=letsencrypt",
        ]
        check {
          type     = "http"
          path     = "/ready"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}