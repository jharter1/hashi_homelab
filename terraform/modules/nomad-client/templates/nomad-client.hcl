datacenter = "${datacenter}"
region = "${region}"
data_dir = "/opt/nomad"
log_file = "/var/log/nomad/nomad.log"
log_level = "INFO"

client {
  enabled = true
  node_class = "${node_class}"
  
  # Reserve minimal system resources, leaving more available for jobs
  reserved {
    cpu      = 250   # MHz - minimal overhead
    memory   = 256   # MB - minimal overhead
    disk     = 1000  # MB - minimal overhead for task directories (1GB safe margin)
  }
  
  server_join {
    retry_join = ${server_addresses}
    retry_interval = "15s"
  }
  
  host_volume "prometheus_data" {
    path = "/mnt/nas/prometheus"
    read_only = false
  }

  host_volume "grafana_data" {
    path = "/mnt/nas/grafana"
    read_only = false
  }

  host_volume "minio_data" {
    path = "/mnt/nas/minio"
    read_only = false
  }
}

plugin "docker" {
  config {
    allow_privileged = false
    volumes {
      enabled = true
    }
  }
}

plugin "raw_exec" {
  config {
    enabled = true
  }
}

consul {
  address = "127.0.0.1:8500"
  server_service_name = "nomad"
  server_auto_join = true
  client_service_name = "nomad-client"
  client_auto_join = true
  auto_advertise = true
}

telemetry {
  collection_interval = "1s"
  disable_hostname = false
  prometheus_metrics = true
  publish_allocation_metrics = true
  publish_node_metrics = true
}
