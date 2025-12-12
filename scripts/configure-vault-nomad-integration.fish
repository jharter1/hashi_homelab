#!/usr/bin/env fish

# Configure Hub Vault for Nomad Integration
# Sets up JWT auth backend and policies for Nomad workload identity

set -x VAULT_ADDR http://10.0.0.30:8200
# Set VAULT_TOKEN from credentials file or export manually
# source ansible/.vault-hub-credentials
if not set -q VAULT_TOKEN
    echo "❌ Error: VAULT_TOKEN not set. Source credentials file first."
    echo "   Run: source ansible/.vault-hub-credentials"
    exit 1
end

echo "🔐 Configuring Hub Vault for Nomad Integration..."
echo ""

# Enable JWT auth backend for Nomad
echo "📝 Step 1: Enable JWT auth backend..."
vault auth enable -path=jwt-nomad jwt 2>/dev/null; or echo "  ℹ️  jwt-nomad already enabled"

# Get Nomad server OIDC discovery URL
set NOMAD_ADDR "http://10.0.0.50:4646"  # First Nomad server

echo ""
echo "📝 Step 2: Configure JWT auth backend..."
vault write auth/jwt-nomad/config \
    oidc_discovery_url="$NOMAD_ADDR" \
    default_role="nomad-workloads"

echo ""
echo "📝 Step 3: Create Nomad workload policy..."
vault policy write nomad-workloads - << 'EOF'
# Allow reading secrets for Nomad workloads
path "secret/data/nomad/*" {
  capabilities = ["read"]
}

# Allow reading from intermediate PKI for certificate issuance
path "pki_int/issue/homelab-dot-local" {
  capabilities = ["create", "update"]
}

# Allow reading PKI CA chain
path "pki_int/ca_chain" {
  capabilities = ["read"]
}
EOF

echo ""
echo "📝 Step 4: Create JWT role for Nomad workloads..."
vault write auth/jwt-nomad/role/nomad-workloads \
    role_type="jwt" \
    bound_audiences="vault.io" \
    user_claim="/nomad_job_id" \
    user_claim_json_pointer=true \
    claim_mappings="/nomad_namespace"="nomad_namespace" \
    claim_mappings="/nomad_job_id"="nomad_job_id" \
    claim_mappings="/nomad_task"="nomad_task" \
    token_type="service" \
    token_policies="nomad-workloads" \
    token_period="30m" \
    token_explicit_max_ttl="1h"

echo ""
echo "✅ Hub Vault configured for Nomad!"
echo ""
echo "📊 Summary:"
echo "  • JWT auth backend: auth/jwt-nomad"
echo "  • Policy: nomad-workloads"
echo "  • Secrets path: secret/nomad/*"
echo "  • PKI issuance: pki_int/issue/homelab-dot-local"
echo ""
echo "🔄 Next: Restart Nomad servers and clients to pick up new Vault address"
echo ""
echo "  # Restart all Nomad servers"
echo "  ansible nomad_servers -i ansible/inventory/hosts.yml -b -m systemd -a 'name=nomad state=restarted'"
echo ""
echo "  # Restart all Nomad clients"
echo "  ansible nomad_clients -i ansible/inventory/hosts.yml -b -m systemd -a 'name=nomad state=restarted'"
