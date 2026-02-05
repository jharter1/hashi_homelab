#!/usr/bin/env fish

# Fix Vault Policy for PostgreSQL Access
# This updates the nomad-workloads policy to allow access to postgres secrets

set -x VAULT_ADDR http://10.0.0.30:8200

# Check if VAULT_TOKEN is set
if not set -q VAULT_TOKEN
    echo "❌ Error: VAULT_TOKEN not set!"
    echo "Please source credentials first:"
    echo "  source .credentials"
    exit 1
end

echo "🔐 Updating Vault policy to allow postgres/* access..."

# Create policy file
echo '# Allow reading nomad-specific secrets
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
}' | vault policy write nomad-workloads -

if test $status -eq 0
    echo "✅ Policy updated successfully!"
    echo ""
    echo "Next steps:"
    echo "1. Update Nomad configs: cd ansible && ansible-playbook playbooks/site.yml"
    echo "2. Restart Nomad servers and clients"
    echo "3. Deploy PostgreSQL job: nomad job run jobs/services/postgresql.nomad.hcl"
else
    echo "❌ Failed to update policy"
    exit 1
end
