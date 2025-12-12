job "vault-write-test" {
  datacenters = ["dc1"]
  
  group "test" {
    count = 1
    
    task "test" {
      driver = "docker"
      
      config {
        image = "hashicorp/vault:latest"
        command = "sh"
        args = ["-c", "vault write pki_int/issue/service common_name=nomad-test.home ttl=1h && sleep 3600"]
      }
      
      vault {}
      
      env {
        VAULT_ADDR = "http://10.0.0.30:8200"
        VAULT_TOKEN_FILE = "/secrets/vault_token"
      }
      
      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
}
