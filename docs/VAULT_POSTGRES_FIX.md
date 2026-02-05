# Vault-PostgreSQL Integration Fix

## The Problem

Your PostgreSQL secrets are failing because:
1. Secrets are stored at `secret/postgres/*` 
2. Vault policy only allows `secret/nomad/*`
3. Nomad clients aren't configured for workload identity

## The Solution (Choose One)

### Option A: Update Vault Policy (Recommended)

This allows jobs to access both `secret/nomad/*` and `secret/postgres/*`:

```bash
# Source credentials first
source .credentials

# Update policy
vault policy write nomad-workloads - <<EOF
# Allow reading nomad-specific secrets
path "secret/data/nomad/*" {
  capabilities = ["read", "list"]
}

# Allow reading database credentials
path "secret/data/postgres/*" {
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
EOF
```

### Option B: Reorganize Secrets

Move all secrets under `secret/nomad/`:

```bash
# Source credentials first
source .credentials

# Copy secrets to new location
vault kv get -format=json secret/postgres/admin | \
  jq -r '.data.data.password' | \
  vault kv put secret/nomad/postgres/admin password=-

vault kv get -format=json secret/postgres/freshrss | \
  jq -r '.data.data.password' | \
  vault kv put secret/nomad/postgres/freshrss password=-

vault kv get -format=json secret/postgres/gitea | \
  jq -r '.data.data.password' | \
  vault kv put secret/nomad/postgres/gitea password=-

vault kv get -format=json secret/postgres/nextcloud | \
  jq -r '.data.data.password' | \
  vault kv put secret/nomad/postgres/nextcloud password=-

vault kv get -format=json secret/postgres/authelia | \
  jq -r '.data.data.password' | \
  vault kv put secret/nomad/postgres/authelia password=-

vault kv get -format=json secret/postgres/grafana | \
  jq -r '.data.data.password' | \
  vault kv put secret/nomad/postgres/grafana password=-
```

Then update job files to use `secret/data/nomad/postgres/*` instead.

## Update Nomad Configuration

### 1. Update Server Config

Edit `/Users/jackharter/Developer/hashi_homelab/ansible/roles/nomad-server/templates/nomad-server.hcl.j2`:

Change the vault block from:
```hcl
vault {
  enabled = true
  address = "http://10.0.0.30:8200"
  token   = "{{ vault_token | default('') }}"
}
```

To:
```hcl
vault {
  enabled = true
  address = "http://10.0.0.30:8200"
  
  # JWT authentication
  jwt_auth_backend_path = "jwt-nomad"
  
  default_identity {
    aud  = ["vault.io"]
    ttl  = "1h"
  }
}
```

### 2. Update Client Config

The client config is already correct! It just needs the `jwt_auth_backend_path`.

Edit `/Users/jackharter/Developer/hashi_homelab/ansible/roles/nomad-client/templates/nomad-client.hcl.j2`:

Change vault block from:
```hcl
vault {
  enabled = true
  address = "http://10.0.0.30:8200"
}
```

To:
```hcl
vault {
  enabled = true
  address = "http://10.0.0.30:8200"
  jwt_auth_backend_path = "jwt-nomad"
}
```

### 3. Remove Token from Server Config

Edit `/Users/jackharter/Developer/hashi_homelab/ansible/inventory/group_vars/nomad_servers.yml`:

```yaml
---
# Consul server configuration
consul_server: true
consul_bootstrap_expect: 3

# Nomad server configuration
nomad_bootstrap_expect: 3

# Vault integration - JWT auth (no token needed!)
# Remove or comment out: vault_token: "..."
```

## Update PostgreSQL Job

Add the `vault{}` block to enable workload identity:

```hcl
job "postgresql" {
  datacenters = ["dc1"]
  type        = "service"

  group "postgres" {
    count = 1

    network {
      mode = "host"
      port "db" {
        static = 5432
      }
    }

    volume "postgres_data" {
      type   = "host"
      source = "postgres_data"
    }

    task "postgres" {
      driver = "docker"

      # Enable Vault workload identity
      vault {}

      config {
        image        = "postgres:16-alpine"
        network_mode = "host"
        ports        = ["db"]
      }

      volume_mount {
        volume      = "postgres_data"
        destination = "/var/lib/postgresql/data"
      }

      # Template will now use workload identity token automatically
      template {
        destination = "secrets/postgres.env"
        env         = true
        data        = <<EOH
POSTGRES_PASSWORD={{ with secret "secret/data/postgres/admin" }}{{ .Data.data.password }}{{ end }}
EOH
      }

      # ... rest of config ...
    }
  }
}
```

## Deployment Steps

1. **Update Vault policy:**
   ```bash
   fish scripts/update-vault-policy.fish  # You'll need to create this
   # Or run the vault policy write command manually
   ```

2. **Update Ansible configs and deploy:**
   ```bash
   cd ansible
   ansible-playbook playbooks/site.yml
   ```

3. **Restart Nomad servers:**
   ```bash
   ssh ubuntu@10.0.0.50 "sudo systemctl restart nomad"
   ssh ubuntu@10.0.0.51 "sudo systemctl restart nomad"
   ssh ubuntu@10.0.0.52 "sudo systemctl restart nomad"
   ```

4. **Restart Nomad clients:**
   ```bash
   ssh ubuntu@10.0.0.60 "sudo systemctl restart nomad"
   ssh ubuntu@10.0.0.61 "sudo systemctl restart nomad"
   ssh ubuntu@10.0.0.62 "sudo systemctl restart nomad"
   ```

5. **Deploy PostgreSQL:**
   ```bash
   nomad job run jobs/services/postgresql.nomad.hcl
   ```

## Verification

```bash
# Check job status
nomad job status postgresql

# Check allocation logs
nomad alloc logs -f <alloc-id> postgres

# Verify vault token was created
ssh ubuntu@10.0.0.61 "sudo ls -la /opt/nomad/alloc/*/postgres/secrets/"

# Should see:
# - vault_token
# - nomad_vault_default.jwt
# - postgres.env (with actual password)
```

## PKI Certificates (Separate Issue)

The PKI template write issue is a known limitation. For now, use one of these workarounds:

### Workaround 1: Let's Encrypt with Traefik

Traefik has built-in ACME support. If you have a public domain, this is the easiest path:

```hcl
# In Traefik job
env {
  TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_EMAIL = "your@email.com"
  TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_STORAGE = "/letsencrypt/acme.json"
  TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_HTTPCHALLENGE_ENTRYPOINT = "web"
}
```

### Workaround 2: Init Container with Vault CLI

Use a prestart task to issue the certificate:

```hcl
task "issue-cert" {
  driver = "docker"
  
  lifecycle {
    hook = "prestart"
  }
  
  vault {}
  
  config {
    image = "hashicorp/vault:latest"
    command = "/bin/sh"
    args = ["-c", <<EOF
vault write -format=json pki_int/issue/service \
  common_name=*.home \
  alt_names=home \
  ttl=720h > /tmp/cert.json

cat /tmp/cert.json | jq -r .data.certificate > ${NOMAD_ALLOC_DIR}/tls.crt
cat /tmp/cert.json | jq -r .data.private_key > ${NOMAD_ALLOC_DIR}/tls.key
cat /tmp/cert.json | jq -r .data.issuing_ca > ${NOMAD_ALLOC_DIR}/ca.crt
EOF
    ]
  }
  
  env {
    VAULT_ADDR = "http://10.0.0.30:8200"
  }
}
```

### Workaround 3: Self-Signed Certificates

For homelab, self-signed certs work fine:

```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /mnt/nas/traefik/tls.key \
  -out /mnt/nas/traefik/tls.crt \
  -subj "/CN=*.home"
```

Mount these as host volumes in Traefik.

## Why This Will Work

1. **JWT auth eliminates token management** - no more expired tokens!
2. **Workload identity is per-allocation** - better security
3. **Policy fix allows access to your secrets** - this was the blocker
4. **KV reads work perfectly with workload identity** - proven in your testing

The PKI issue is separate and requires a workaround until Nomad/Consul-Template adds better support for write operations.
