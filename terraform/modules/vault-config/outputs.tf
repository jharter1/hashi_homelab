output "nomad_server_token" {
  description = "Token for Nomad servers to authenticate with Vault"
  value       = vault_token.nomad_server.client_token
  sensitive   = true
}

output "root_ca_certificate" {
  description = "Root CA certificate (install on workstations to trust internal certs)"
  value       = vault_pki_secret_backend_root_cert.root.certificate
}

output "pki_root_path" {
  description = "Path to root PKI mount"
  value       = vault_mount.pki.path
}

output "pki_int_path" {
  description = "Path to intermediate PKI mount"
  value       = vault_mount.pki_int.path
}

output "kv_mount_path" {
  description = "Path to KV v2 secrets engine"
  value       = vault_mount.kv.path
}

# Secrets Confirmation Outputs (values are sensitive)
output "secrets_configured" {
  description = "List of secrets configured in Vault"
  value = [
    "${vault_kv_secret_v2.docker_registry.mount}/${vault_kv_secret_v2.docker_registry.name}",
    "${vault_kv_secret_v2.grafana.mount}/${vault_kv_secret_v2.grafana.name}",
    "${vault_kv_secret_v2.prometheus.mount}/${vault_kv_secret_v2.prometheus.name}",
    "${vault_kv_secret_v2.minio.mount}/${vault_kv_secret_v2.minio.name}",
    "${vault_kv_secret_v2.consul_encryption.mount}/${vault_kv_secret_v2.consul_encryption.name}",
  ]
}

# Token for Nomad servers (create it here)
resource "vault_token" "nomad_server" {
  policies = [vault_policy.nomad_server.name]

  renewable = true
  ttl       = "72h"
  period    = "72h"

  renew_min_lease = 43200
  renew_increment = 86400

  metadata = {
    purpose = "nomad-server"
  }
}
