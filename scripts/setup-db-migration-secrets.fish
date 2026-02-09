#!/usr/bin/env fish
# Setup Vault secrets for database migration
# This script creates secure passwords in Vault for services migrating to PostgreSQL

set -x VAULT_ADDR "http://10.0.0.30:8200"

echo "🔐 Setting up Vault secrets for database migration..."
echo ""

# Generate secure random passwords
function generate_password
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
end

# Create secrets for new databases
echo "Creating secret for Immich database..."
vault kv put secret/postgres/immich password=(generate_password)

echo "Creating secret for Speedtest database..."
vault kv put secret/postgres/speedtest password=(generate_password)

echo "Creating secret for Uptime-Kuma database..."
vault kv put secret/postgres/uptimekuma password=(generate_password)

echo "Creating secret for Vaultwarden database..."
vault kv put secret/postgres/vaultwarden password=(generate_password)

echo ""
echo "✅ Vault secrets created successfully!"
echo ""
echo "Next steps:"
echo "1. Redeploy PostgreSQL to initialize new databases:"
echo "   nomad job stop postgresql && nomad job run jobs/services/postgresql.nomad.hcl"
echo ""
echo "2. Wait for PostgreSQL to initialize (~30 seconds)"
echo ""
echo "3. Redeploy migrated services:"
echo "   nomad job run jobs/services/immich.nomad.hcl"
echo "   nomad job run jobs/services/speedtest.nomad.hcl"
echo "   nomad job run jobs/services/uptime-kuma.nomad.hcl"
echo "   nomad job run jobs/services/vaultwarden.nomad.hcl"
