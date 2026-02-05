#!/usr/bin/env fish

# Setup JWT Auth Backend for Nomad Workload Identity
# This configures Vault to accept JWT tokens from Nomad allocations

set -x VAULT_ADDR http://10.0.0.30:8200

# Check if VAULT_TOKEN is set
if not set -q VAULT_TOKEN
    echo "❌ Error: VAULT_TOKEN not set!"
    echo "Please source credentials first:"
    echo "  source .credentials"
    exit 1
end

echo "🔐 Setting up JWT auth backend for Nomad..."

# Enable JWT auth backend
echo "1. Enabling JWT auth at jwt-nomad path..."
vault auth enable -path=jwt-nomad jwt
if test $status -ne 0
    echo "⚠️  JWT auth already enabled or error occurred"
end

# Configure JWT auth backend
echo "2. Configuring JWT auth backend..."
# Get JWKS from Nomad server
set jwks_url "http://10.0.0.50:4646/.well-known/jwks.json"

vault write auth/jwt-nomad/config \
    jwks_url="$jwks_url" \
    default_role="nomad-workloads"

# Create role for Nomad workloads
echo "3. Creating nomad-workloads role..."
vault write auth/jwt-nomad/role/nomad-workloads \
    role_type="jwt" \
    bound_audiences="vault.io" \
    user_claim="nomad_job_id" \
    user_claim_json_pointer=true \
    claim_mappings="/nomad_namespace"="nomad_namespace" \
    claim_mappings="/nomad_job_id"="nomad_job_id" \
    claim_mappings="/nomad_task"="nomad_task" \
    token_type="service" \
    token_policies="nomad-workloads" \
    token_period="30m" \
    token_explicit_max_ttl="1h"

if test $status -eq 0
    echo "✅ JWT auth backend configured successfully!"
    echo ""
    echo "Next step: Redeploy PostgreSQL job"
    echo "  nomad job run jobs/services/postgresql.nomad.hcl"
else
    echo "❌ Failed to configure JWT auth"
    exit 1
end
