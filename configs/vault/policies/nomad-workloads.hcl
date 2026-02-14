# Allow reading nomad-specific secrets
path "secret/data/nomad/*" {
  capabilities = ["read", "list"]
}

# Allow reading database credentials
path "secret/data/postgres/*" {
  capabilities = ["read", "list"]
}

# Allow reading MariaDB credentials
path "secret/data/mariadb/*" {
  capabilities = ["read", "list"]
}

# Allow reading authelia configuration
path "secret/data/authelia/*" {
  capabilities = ["read", "list"]
}

# Allow reading linkwarden secrets
path "secret/data/linkwarden/*" {
  capabilities = ["read", "list"]
}

# Allow reading wallabag secrets
path "secret/data/wallabag/*" {
  capabilities = ["read", "list"]
}

# Allow reading paperless secrets
path "secret/data/paperless/*" {
  capabilities = ["read", "list"]
}

# Allow reading harbor secrets
path "secret/data/harbor/*" {
  capabilities = ["read", "list"]
}

# Allow reading woodpecker secrets
path "secret/data/woodpecker/*" {
  capabilities = ["read", "list"]
}

# Allow listing secret paths
path "secret/metadata/*" {
  capabilities = ["list"]
}

# PKI access (for future use)
path "pki_int/issue/service" {
  capabilities = ["create", "update"]
}
