#!/usr/bin/env fish
# Setup Authelia Secrets in Vault
# This script generates cryptographically secure secrets and stores them in Vault

set -x VAULT_ADDR http://10.0.0.30:8200

echo "🔐 Setting up Authelia secrets in Vault..."
echo ""

# Check if Vault is accessible
if not vault status >/dev/null 2>&1
    echo "❌ Error: Cannot connect to Vault at $VAULT_ADDR"
    echo "   Make sure Vault is running"
    exit 1
end

echo "✓ Vault is accessible"

# Check if authenticated
if not vault token lookup >/dev/null 2>&1
    echo "❌ Error: Not authenticated with Vault"
    echo ""
    echo "   Authenticate first:"
    echo "   set -x VAULT_TOKEN hvs.YOUR_ROOT_TOKEN"
    echo ""
    echo "   Or source your credentials file:"
    echo "   source ansible/.vault-hub-credentials"
    exit 1
end

echo "✓ Vault authentication valid"
echo ""

# Generate cryptographically secure secrets
echo "🎲 Generating secrets..."
set jwt_secret (openssl rand -base64 48)
set session_secret (openssl rand -base64 48)
set encryption_key (openssl rand -base64 32)

echo "✓ Generated JWT secret (48 bytes)"
echo "✓ Generated session secret (48 bytes)"
echo "✓ Generated encryption key (32 bytes)"
echo ""

# Store in Vault
echo "💾 Storing secrets in Vault..."
vault kv put secret/authelia/config \
    jwt_secret="$jwt_secret" \
    session_secret="$session_secret" \
    encryption_key="$encryption_key"

if test $status -eq 0
    echo "✅ Secrets stored successfully at secret/authelia/config"
    echo ""
    
    # Verify storage
    echo "🔍 Verifying storage..."
    vault kv get secret/authelia/config >/dev/null 2>&1
    
    if test $status -eq 0
        echo "✅ Verification successful!"
        echo ""
        echo "📋 Next steps:"
        echo "   1. Generate password hash: ./scripts/generate-authelia-password.fish"
        echo "   2. Update authelia.nomad.hcl with the hash"
        echo "   3. Deploy: nomad job run jobs/services/authelia.nomad.hcl"
    else
        echo "⚠️  Warning: Could not verify secrets (but they may have been stored)"
    end
else
    echo "❌ Error: Failed to store secrets in Vault"
    exit 1
end
