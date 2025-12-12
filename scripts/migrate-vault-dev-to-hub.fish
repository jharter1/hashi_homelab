#!/usr/bin/env fish

# Vault Migration Script: Dev (10.0.0.50) -> Hub (10.0.0.30)
# Migrates KV secrets, PKI configuration, and policies

echo "🔄 Starting Vault migration from dev to hub..."

# Source Vault (dev)
set -x DEV_VAULT_ADDR http://10.0.0.50:8200
# Set tokens from environment or credential files
if not set -q DEV_VAULT_TOKEN
    echo "❌ Error: DEV_VAULT_TOKEN not set"
    echo "   Export your dev vault token first"
    exit 1
end

# Destination Vault (hub)
set -x HUB_VAULT_ADDR http://10.0.0.30:8200
if not set -q HUB_VAULT_TOKEN
    echo "❌ Error: HUB_VAULT_TOKEN not set"
    echo "   Source: ansible/.vault-hub-credentials"
    exit 1
end

echo ""
echo "📦 Step 1: Enable secrets engines on hub Vault..."

# Enable KV v2 secrets engine
set -x VAULT_ADDR $HUB_VAULT_ADDR
set -x VAULT_TOKEN $HUB_VAULT_TOKEN
vault secrets enable -version=2 -path=secret kv 2>/dev/null; or echo "  ℹ️  secret/ already enabled"

# Enable PKI engines
vault secrets enable -path=pki pki 2>/dev/null; or echo "  ℹ️  pki/ already enabled"
vault secrets enable -path=pki_int pki 2>/dev/null; or echo "  ℹ️  pki_int/ already enabled"

echo ""
echo "🔐 Step 2: Export and import KV secrets..."

# Function to migrate a secret
function migrate_secret
    set secret_path $argv[1]
    echo "  → Migrating $secret_path"
    
    # Read from dev
    set -x VAULT_ADDR $DEV_VAULT_ADDR
    set -x VAULT_TOKEN $DEV_VAULT_TOKEN
    set secret_data (vault kv get -format=json $secret_path | jq -r '.data.data')
    
    # Write to hub
    set -x VAULT_ADDR $HUB_VAULT_ADDR
    set -x VAULT_TOKEN $HUB_VAULT_TOKEN
    echo $secret_data | vault kv put $secret_path -
end

# Migrate consul secrets
migrate_secret secret/consul/encryption

# Migrate nomad secrets
for app in codeserver docker-registry grafana minio prometheus
    migrate_secret secret/nomad/$app
end

echo ""
echo "🔑 Step 3: Export root CA from dev Vault..."

set -x VAULT_ADDR $DEV_VAULT_ADDR
set -x VAULT_TOKEN $DEV_VAULT_TOKEN

# Export root CA certificate and key
vault read -field=certificate pki/cert/ca > /tmp/root_ca.crt
vault read -field=private_key pki/cert/ca_chain > /tmp/root_ca.key 2>/dev/null

echo ""
echo "📋 Step 4: Configure PKI on hub Vault..."

set -x VAULT_ADDR $HUB_VAULT_ADDR
set -x VAULT_TOKEN $HUB_VAULT_TOKEN

# Configure PKI max lease TTL
vault secrets tune -max-lease-ttl=87600h pki
vault secrets tune -max-lease-ttl=43800h pki_int

# Import root CA (if we have the key) or generate new
if test -f /tmp/root_ca.key
    echo "  → Importing existing root CA"
    vault write pki/config/ca pem_bundle=@/tmp/root_ca.crt
else
    echo "  → Generating new root CA (old key not accessible)"
    vault write -field=certificate pki/root/generate/internal \
        common_name="Homelab Root CA" \
        issuer_name="root-2024" \
        ttl=87600h > /tmp/new_root_ca.crt
end

# Configure PKI URLs (update to point to hub)
vault write pki/config/urls \
    issuing_certificates="http://10.0.0.30:8200/v1/pki/ca" \
    crl_distribution_points="http://10.0.0.30:8200/v1/pki/crl"

# Generate intermediate CA
vault write -format=json pki_int/intermediate/generate/internal \
    common_name="Homelab Intermediate CA" \
    issuer_name="homelab-intermediate" \
    ttl=43800h | jq -r '.data.csr' > /tmp/pki_intermediate.csr

# Sign intermediate with root
vault write -format=json pki/root/sign-intermediate \
    issuer_ref="root-2024" \
    csr=@/tmp/pki_intermediate.csr \
    format=pem_bundle \
    ttl=43800h | jq -r '.data.certificate' > /tmp/intermediate.cert.pem

# Import signed intermediate
vault write pki_int/intermediate/set-signed certificate=@/tmp/intermediate.cert.pem

# Create role for issuing certificates
vault write pki_int/roles/homelab-dot-local \
    allowed_domains="homelab.local" \
    allow_subdomains=true \
    max_ttl="720h"

# Configure intermediate URLs
vault write pki_int/config/urls \
    issuing_certificates="http://10.0.0.30:8200/v1/pki_int/ca" \
    crl_distribution_points="http://10.0.0.30:8200/v1/pki_int/crl"

echo ""
echo "✅ Migration complete!"
echo ""
echo "📊 Summary:"
echo "  • KV secrets migrated: consul/encryption, nomad/* (5 apps)"
echo "  • PKI engines configured with root and intermediate CA"
echo "  • Hub Vault: http://10.0.0.30:8200"
echo ""
echo "⚠️  Next steps:"
echo "  1. Update Nomad servers to use hub Vault (10.0.0.30:8200)"
echo "  2. Test certificate issuance from pki_int/issue/homelab-dot-local"
echo "  3. Update terraform to reference hub Vault"
echo "  4. Consider decommissioning dev Vault at 10.0.0.50"
echo ""

# Cleanup temp files
rm -f /tmp/root_ca.crt /tmp/root_ca.key /tmp/pki_intermediate.csr /tmp/intermediate.cert.pem /tmp/new_root_ca.crt
