job "vault-test" {
  datacenters = ["dc1"]

  group "test" {
    task "env" {
      driver = "docker"

      vault {
        cluster  = "default"
        policies = ["access-secrets"]
      }

      template {
        data        = <<EOT
{{ with secret "secret/data/nomad/grafana" }}
GRAFANA_PASSWORD="{{ .Data.data.admin_password }}"
{{ end }}
EOT
        destination = "secrets/file.env"
        env         = true
      }

      config {
        image   = "alpine:latest"
        command = "sh"
        args    = ["-c", "echo 'Grafana password from Vault:' && echo $GRAFANA_PASSWORD && sleep 30"]
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
}
