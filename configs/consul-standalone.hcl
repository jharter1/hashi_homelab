datacenter = "dc1"
data_dir = "/opt/consul/data"
log_level = "INFO"

# Run as server for standalone mode
server = true
bootstrap_expect = 1

# Bind to all interfaces
bind_addr = "0.0.0.0"
client_addr = "0.0.0.0"

# Enable UI
ui_config {
  enabled = true
}

# Performance tuning
performance {
  raft_multiplier = 1
}

# Telemetry
telemetry {
  disable_hostname = false
  prometheus_retention_time = "24h"
}
