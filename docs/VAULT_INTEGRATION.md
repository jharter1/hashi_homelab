# Phase 1: Vault Integration Guide

This guide walks through integrating HashiCorp Vault into your homelab for secrets management and PKI using Infrastructure as Code.

## Overview

Vault will provide:

- **Internal PKI/CA** for issuing TLS certificates to services
- **Secrets storage** for application credentials and API keys
- **Dynamic secrets** for databases and other systems
- **Integration with Nomad** for automatic secret injection

## Architecture

```
┌─────────────────┐
│  Ansible        │ → Installs Vault, initializes, stores credentials
├─────────────────┤
│  Terraform      │ → Configures PKI, policies, roles, secrets
├─────────────────┤
│  Nomad Jobs     │ → Fetch secrets via Vault integration
└─────────────────┘
```

## Prerequisites

- Nomad and Consul clusters running
- Ansible installed locally
- Terraform installed locally
- SSH access to servers

## Quick Start (Automated)

Run the automated setup script:

```bash
./scripts/setup-vault.fish
```

This will:
1. Install Vault via Ansible on your first Nomad server
2. Initialize Vault and save credentials to `ansible/.vault-credentials`
3. Configure PKI, policies, and secrets via Terraform
4. Generate a token for Nomad integration

**That's it!** Skip to [Step 6: Integrate Vault with Nomad](#step-6-integrate-vault-with-nomad)

## Manual Setup (Step by Step)

If you prefer to understand each step or the automated script fails:

## Step 1: Install Vault with Ansible

**Run the Ansible playbook:**

```bash
cd ansible
ansible-playbook -i inventory/hosts.yml playbooks/install-vault.yml
```

This will:
- Install Vault binary
- Create Vault user and directories
- Configure Vault service
- Initialize Vault (first time only)
- Save unseal key and root token to `ansible/.vault-credentials`

**Important:** The credentials file contains sensitive data. Keep it secure!

## Step 2: Configure Vault with Terraform

The Ansible role installed Vault, now Terraform will configure it.

```bash
cd terraform/environments/dev

# Load credentials
source ../../ansible/.vault-credentials

# Set Terraform variables
export TF_VAR_vault_token=$VAULT_ROOT_TOKEN
export TF_VAR_vault_address=$VAULT_ADDR

# Initialize Terraform (first time only)
terraform init

# Apply Vault configuration
terraform apply -target=module.vault_config
```

This creates:
- Root CA and Intermediate CA
- PKI roles (server, client, service)
- Policies for Nomad integration
- KV v2 secrets engine with example secrets
- Token for Nomad servers

## Step 3: Save Important Outputs

```bash
# Save Nomad server token
terraform output -raw nomad_server_token > ~/.nomad-vault-token

# Save root CA certificate
terraform output -raw root_ca_cert > ~/homelab-root-ca.crt
```

## Step 4: Integrate Vault with Nomad

### 4.1 Get the Nomad Server Token

```bash
cd terraform/environments/dev
terraform output -raw nomad_server_token
```

Copy this token - you'll need it for Nomad configuration.

### 4.2 Update Nomad Server Configuration

Add Vault integration to each Nomad server's config file (`/etc/nomad.d/nomad.hcl`):

```hcl
vault {
  enabled          = true
  address          = "http://10.0.0.151:8200"  # Your Vault server
  task_token_ttl   = "1h"
  create_from_role = "nomad-cluster"
  token            = "hvs.your-token-here"  # From step 4.1
}
```

You can do this with Ansible or manually via SSH.

### 4.3 Restart Nomad Servers

```bash
sudo systemctl restart nomad
```

### 4.4 Verify Integration

```bash
nomad server members  # All servers should be healthy
vault token lookup hvs.your-token-here  # Should show token details
```

## Step 5: Use Vault in Nomad Jobs

Now your Nomad jobs can fetch secrets from Vault:

```hcl
job "example" {
  group "app" {
    task "web" {
      driver = "docker"

      vault {
        policies = ["nomad-workloads"]
      }

      template {
        data = <<EOF
{{ with secret "secret/data/nomad/example" }}
DATABASE_URL={{ .Data.data.db_url }}
API_KEY={{ .Data.data.api_key }}
{{ end }}
EOF
        destination = "secrets/app.env"
        env         = true
      }

      config {
        image = "myapp:latest"
      }
    }
  }
}
```

### Example: Fetch PKI Certificate

```hcl
template {
  data = <<EOF
{{ with secret "pki_int/issue/service" "common_name=myapp.service.consul" "ttl=24h" }}
{{ .Data.certificate }}{{ end }}
EOF
  destination = "secrets/tls.crt"
}

template {
  data = <<EOF
{{ with secret "pki_int/issue/service" "common_name=myapp.service.consul" "ttl=24h" }}
{{ .Data.private_key }}{{ end }}
EOF
  destination = "secrets/tls.key"
}
```

## Step 6: Trust Vault's Root CA (Optional)

For your browser to trust certificates issued by Vault:

### macOS

```bash
# Download the root CA
curl http://10.0.0.151:8200/v1/pki/ca/pem -o homelab-root-ca.crt

# Add to system keychain
sudo security add-trusted-cert -d -r trustRoot \
    -k /Library/Keychains/System.keychain homelab-root-ca.crt
```

### Linux

```bash
sudo cp /tmp/root_ca.crt /usr/local/share/ca-certificates/homelab-root-ca.crt
sudo update-ca-certificates
```

### Windows

1. Download the root CA certificate
2. Double-click the certificate file
3. Click "Install Certificate"
4. Choose "Local Machine" → "Trusted Root Certification Authorities"

## Next Steps

Now that Vault is integrated:

1. **Phase 2**: Set up Traefik with Let's Encrypt for automatic HTTPS
2. **Phase 3**: Configure consul-template for automatic certificate rotation
3. **Migrate existing secrets** from job files to Vault
4. **Set up database dynamic secrets** (if using databases)

## Troubleshooting

### Vault is sealed after restart

Vault seals itself on restart for security. Unseal it:

```bash
export VAULT_ADDR='http://10.0.0.151:8200'
vault operator unseal
```

### Nomad can't connect to Vault

Check:
- Vault is running: `vault status`
- Nomad can reach Vault: `curl http://10.0.0.151:8200/v1/sys/health`
- Token is valid: `vault token lookup <TOKEN>`

### "Permission denied" errors in Nomad jobs

The job needs the correct policy in its `vault` block:

```hcl
vault {
  policies = ["nomad-workloads"]
}
```

## Security Recommendations

For production use:

1. **Enable TLS** on Vault (use certificates from Vault's own PKI once bootstrapped)
2. **Use auto-unseal** with cloud KMS or Transit seal
3. **Rotate the root token** after initial setup
4. **Use AppRole** or other auth methods instead of tokens where possible
5. **Enable audit logging** for compliance
6. **Regular backups** of Vault data
7. **Implement proper ACL policies** with principle of least privilege

## Reference

- [Vault Documentation](https://www.vaultproject.io/docs)
- [Nomad Vault Integration](https://www.nomadproject.io/docs/integrations/vault)
- [Vault PKI Secrets Engine](https://www.vaultproject.io/docs/secrets/pki)
