#!/usr/bin/env fish
# Update Vault policy to allow Authelia secrets access

set -x VAULT_ADDR http://10.0.0.30:8200

echo "🔐 Updating Vault policy for Authelia..."
echo ""

# Check authentication
if not vault token lookup >/dev/null 2>&1
    echo "❌ Error: Not authenticated with Vault"
    echo "   Set: set -x VAULT_TOKEN hvs.YOUR_ROOT_TOKEN"
    exit 1
end

echo "✓ Vault authenticated"
echo ""

# Read current policy
echo "Reading current nomad-workloads policy..."
set current_policy (vault policy read nomad-workloads 2>/dev/null)

if test -z "$current_policy"
    echo "Creating new nomad-workloads policy..."
    set policy_exists "no"
else
    echo "✓ Policy exists, will update"
    set policy_exists "yes"
end

# Create updated policy with Authelia secrets access
echo ""
echo "Updating policy to include Authelia secrets..."

vault policy write nomad-workloads - << 'EOF'
# Allow Nomad workloads to read secrets
path "secret/data/*" {
  capabilities = ["read"]
}

path "secret/metadata/*" {
  capabilities = ["list", "read"]
}

# Allow reading Authelia configuration
path "secret/data/authelia/*" {
  capabilities = ["read"]
}

# Allow reading PostgreSQL credentials
path "secret/data/postgres/*" {
  capabilities = ["read"]
}

# Allow reading Nomad-specific secrets
path "secret/data/nomad/*" {
  capabilities = ["read"]
}
EOF

if test $status -eq 0
    echo ""
    echo "✅ Policy updated successfully!"
    echo ""
    echo "The nomad-workloads policy now includes:"
    echo "  - secret/data/authelia/* (read)"
    echo "  - secret/data/postgres/* (read)"
    echo "  - secret/data/nomad/* (read)"
    echo "  - secret/data/* (read)"
    echo ""
    echo "Redeploy Authelia:"
    echo "  nomad job run jobs/services/authelia.nomad.hcl"
else
    echo ""
    echo "❌ Failed to update policy"
    exit 1
end
