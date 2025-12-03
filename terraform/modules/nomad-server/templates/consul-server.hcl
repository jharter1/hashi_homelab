datacenter = "${datacenter}"
data_dir = "/opt/consul"
log_file = "/var/log/consul/consul.log"
log_level = "INFO"

server = true
bootstrap_expect = ${server_count}

retry_join = ${consul_retry_join}

bind_addr = "0.0.0.0"
client_addr = "0.0.0.0"

connect {
  enabled = true
}

ui_config {
  enabled = true
}

performance {
  raft_multiplier = 1
}
