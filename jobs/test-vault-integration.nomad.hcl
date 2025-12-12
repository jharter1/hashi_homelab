job "vault-integration-test" {
  datacenters = ["dc1"]
  type = "batch"

  group "test" {
    count = 1

    task "read-secret" {
      driver = "docker"

      config {
        image = "alpine:latest"
        command = "sh"
        args = ["-c", "echo 'Testing Vault integration'; cat ${NOMAD_SECRETS_DIR}/secret.txt; sleep 5"]
      }

      vault {
        policies = ["nomad-workloads"]
      }

      template {
        data = <<EOF
{{with secret "secret/data/nomad/test"}}
Secret value: {{.Data.data.value}}
{{end}}
EOF
        destination = "${NOMAD_SECRETS_DIR}/secret.txt"
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
}
