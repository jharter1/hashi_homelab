# Vault Integration: Standard Policy
# Standard Vault policy for Nomad workloads

vault {
  policies    = ["nomad-workloads"]
  change_mode = "restart"
}
