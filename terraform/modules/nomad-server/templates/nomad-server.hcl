datacenter = "${datacenter}"
region = "${region}"
data_dir = "/opt/nomad"
log_file = "/var/log/nomad/nomad.log"
log_level = "INFO"

server {
  enabled = true
  bootstrap_expect = ${server_count}
  
  server_join {
    retry_join = ${consul_retry_join}
    retry_interval = "15s"
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
