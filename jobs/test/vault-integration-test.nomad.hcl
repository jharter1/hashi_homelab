job "vault-integration-test" {
  datacenters = ["dc1"]
  type        = "batch"

  group "test" {
    count = 1

    task "echo-secret" {
      driver = "docker"

      # Vault configuration for this task
      vault {
        policies = ["nomad-workloads"]
      }

      # Template to fetch secret from Vault
      template {
        data = <<EOF
{{ with secret "secret/data/nomad/default/test" }}
USERNAME={{ .Data.data.username }}
PASSWORD={{ .Data.data.password }}
MESSAGE={{ .Data.data.message }}
{{ end }}
EOF
        destination = "secrets/credentials.env"
        env         = true
      }

      config {
        image   = "alpine:latest"
        command = "/bin/sh"
        args    = [
          "-c",
          "echo 'Testing Vault integration...' && env | grep -E '(USERNAME|PASSWORD|MESSAGE)' && echo 'Secret successfully retrieved from Vault!'"
        ]
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
}
