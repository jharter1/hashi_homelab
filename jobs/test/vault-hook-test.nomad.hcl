job "vault-hook-test" {
  datacenters = ["dc1"]
  
  group "test" {
    count = 1
    
    task "test" {
      driver = "docker"
      
      config {
        image = "busybox:1"
        command = "sh"
        args = ["-c", "cat /secrets/vault_token && sleep 3600"]
      }
      
      vault {}
      
      template {
        data        = "{{ with secret \"secret/data/nomad/test\" }}{{ .Data.data.foo }}{{ end }}"
        destination = "local/test.txt"
      }
      
      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
}
