datacenter = "dc1"
data_dir = "/opt/nomad/data"
log_level = "INFO"

# Run as both server and client for standalone mode
server {
  enabled = true
  bootstrap_expect = 1
}

client {
  enabled = true
  
  options = {
    "driver.raw_exec.enable" = "1"
  }
}

# Consul integration
consul {
  address = "127.0.0.1:8500"
  auto_advertise = true
  server_auto_join = true
  client_auto_join = true
}

# Telemetry
telemetry {
  publish_allocation_metrics = true
  publish_node_metrics       = true
  prometheus_metrics         = true
}
