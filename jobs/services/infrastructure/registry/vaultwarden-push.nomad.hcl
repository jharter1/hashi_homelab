job "vaultwarden-push" {
  datacenters = ["dc1"]
  type        = "batch"

  # One-off job: push vaultwarden/server:latest to the local registry with its
  # namespaced path preserved. skopeo-sync would strip the namespace to "server:latest"
  # which is too generic — so this image is excluded from auto-sync.
  # Re-run manually after upstream vaultwarden releases a new tag:
  #   nomad job run jobs/services/infrastructure/registry/vaultwarden-push.nomad.hcl

  group "push" {
    count = 1

    network {
      mode = "host"
    }

    reschedule {
      attempts  = 1
      unlimited = false
    }

    restart {
      attempts = 1
      delay    = "10s"
      interval = "5m"
      mode     = "fail"
    }

    task "skopeo" {
      driver = "docker"

      config {
        image        = "quay.io/skopeo/stable:latest"
        network_mode = "host"
        command      = "copy"
        args = [
          "--dest-tls-verify=true",
          "docker://vaultwarden/server:latest",
          "docker://registry.lab.hartr.net/vaultwarden/server:latest",
        ]
      }

      resources {
        cpu    = 300
        memory = 256
      }
    }
  }
}
