datacenter = "${datacenter}"
region = "${region}"
data_dir = "/opt/nomad"

client {
  enabled = true
  node_class = "${node_class}"
  
  server_join {
    retry_join = ${server_addresses}
    retry_interval = "15s"
  }
  
  host_volume "grafana_data" {
    path = "/mnt/nas/grafana"
    read_only = false
  }
  
  host_volume "loki_data" {
    path = "/mnt/nas/loki"
    read_only = false
  }
  
  host_volume "minio_data" {
    path = "/mnt/nas/minio"
    read_only = false
  }
  
  host_volume "prometheus_data" {
    path = "/mnt/nas/prometheus"
    read_only = false
  }
  
  host_volume "registry_data" {
    path = "/mnt/nas/registry"
    read_only = false
  }
}

bind_addr = "0.0.0.0"

advertise {
  http = "{{ GetInterfaceIP \"ens18\" }}"
  rpc  = "{{ GetInterfaceIP \"ens18\" }}"
  serf = "{{ GetInterfaceIP \"ens18\" }}"
}

consul {
  address = "127.0.0.1:8500"
  auto_advertise = true
  client_service_name = "nomad-client"
  client_auto_join = true
}

plugin "docker" {
  config {
    allow_privileged = false
    volumes {
      enabled = true
    }
  }
}