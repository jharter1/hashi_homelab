datacenter = "${datacenter}"
data_dir = "/opt/consul"
log_file = "/var/log/consul/consul.log"
log_level = "INFO"

server = false

retry_join = ${server_addresses}

bind_addr = "0.0.0.0"
client_addr = "0.0.0.0"

connect {
  enabled = true
}

performance {
  raft_multiplier = 1
}
