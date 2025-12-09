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
        image = "grafana/alloy:latest"
        network_mode = "host"
        # The 'ports' list is mainly for the service stanza below when using host network.
        ports = ["http"] 

        args = [
          "run",
          "--server.http.listen-addr=0.0.0.0:12345",
          "--storage.path=/var/lib/alloy/data",
          "--disable-reporting",
          "/alloy/config.alloy",
        ]

        # 1. Mount the necessary host paths for log scraping/discovery
        volumes = [
          "local/config.alloy:/alloy/config.alloy:ro",
          # For Docker discovery and log scraping
          "/var/run/docker.sock:/var/run/docker.sock:ro",
          "/var/lib/docker/containers:/var/lib/docker/containers:ro",
          # For file log scraping (e.g., /var/log/*.log)
          "/var/log:/var/log:ro", 
        ]
      }

      # 2. The template block that generates the config file
      template {
        # Destination inside the task's allocation directory.
        # Nomad automatically creates a volume named "local" for this directory.
        destination = "local/config.alloy" 
        data = <<EOH
logging {
  level = "info"
}

// Write logs to a Loki endpoint (assuming it's running as a service named "loki")
loki.write "default" {
  endpoint {
    url = "http://{{ range service "loki" }}{{ .Address }}:{{ .Port }}{{ end }}/loki/api/v1/push"
  }
}

// Scrape system logs from the host
loki.source.file "system_logs" {
  targets = [
    {__path__ = "/var/log/*.log", job = "host_logs"},
  ]
  forward_to = [loki.write.default.receiver]
}

// Scrape Docker container logs (using your existing logic)
discovery.docker "containers" {
  host = "unix:///var/run/docker.sock"
}

loki.relabel "docker_relabel" {
  forward_to = [loki.write.default.receiver]
  
  rule {
    source_labels = ["__meta_docker_container_name"]
    regex = "/(.*)"
    target_label = "container"
  }
}

loki.source.docker "containers" {
  host = "unix:///var/run/docker.sock"
  targets = discovery.docker.containers.targets
  forward_to = [loki.relabel.docker_relabel.receiver]
}
EOH
      }

      resources {
        cpu    = 200
        memory = 256
      }

      service {
        name = "alloy"
        port = "http"
        tags = ["logging", "telemetry"]
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