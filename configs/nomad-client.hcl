# Nomad Standalone Client Configuration
# This runs Nomad in client-only mode without requiring a server
datacenter = "dc1"
data_dir = "/opt/nomad/data"
log_level = "INFO"

# Bind to all interfaces
bind_addr = "0.0.0.0"

# Client configuration
client {
  enabled = true
  
  # Network configuration
  network_interface = "eth0"
  
  # Server addresses (empty for now - will need to add when server is available)
  servers = []
  
  # Resource limits
  reserved {
    cpu            = 500
    memory         = 512
    disk           = 1024
  }
}

# Disable Consul integration for now
consul {
  auto_advertise = false
  client_auto_join = false
}

# Vault integration (disabled)
vault {
  enabled = false
}

# Telemetry
telemetry {
  publish_allocation_metrics = true
  publish_node_metrics       = true
  prometheus_metrics         = true
}
