#!/usr/bin/env fish
# Initialize Vault PKI for homelab certificates

set -l vault_addr "http://10.0.0.30:8200"

# Source credentials
if test -f ansible/.vault-hub-credentials
    source ansible/.vault-hub-credentials
else
    echo "Error: Vault credentials not found"
    exit 1
end

echo "🔐 Setting up Vault PKI..."

# Step 1: Generate root CA
echo "📜 Generating root CA..."
set -l root_ca (VAULT_ADDR=$vault_addr VAULT_TOKEN=$VAULT_ROOT_TOKEN vault write -format=json \
    pki/root/generate/internal \
    common_name="Homelab Root CA" \
    issuer_name="root-ca" \
    ttl=87600h | jq -r '.data.certificate')

if test -z "$root_ca"
    echo "❌ Failed to generate root CA"
    exit 1
end

echo "✅ Root CA generated"

# Step 2: Generate intermediate CA CSR
echo "📜 Generating intermediate CA CSR..."
set -l int_csr (VAULT_ADDR=$vault_addr VAULT_TOKEN=$VAULT_ROOT_TOKEN vault write -format=json \
    pki_int/intermediate/generate/internal \
    common_name="Homelab Intermediate CA" \
    issuer_name="intermediate-ca" | jq -r '.data.csr')

if test -z "$int_csr"
    echo "❌ Failed to generate intermediate CSR"
    exit 1
end

# Step 3: Sign intermediate with root CA
echo "🔏 Signing intermediate CA with root..."
# Write CSR to temp file since fish doesn't handle multi-line strings well in command args
printf '%s' "$int_csr" > /tmp/int_csr.pem
set -l int_cert (VAULT_ADDR=$vault_addr VAULT_TOKEN=$VAULT_ROOT_TOKEN vault write -format=json \
    pki/root/sign-intermediate \
    issuer_ref="root-ca" \
    csr=@/tmp/int_csr.pem \
    format=pem_bundle \
    ttl=43800h | jq -r '.data.certificate')
rm /tmp/int_csr.pem

if test -z "$int_cert"
    echo "❌ Failed to sign intermediate CA"
    exit 1
end

# Step 4: Import signed certificate back to intermediate CA
echo "📥 Importing signed intermediate certificate..."
printf '%s' "$int_cert" | VAULT_ADDR=$vault_addr VAULT_TOKEN=$VAULT_ROOT_TOKEN vault write \
    pki_int/intermediate/set-signed \
    certificate=-

echo "✅ Intermediate CA configured"

# Step 5: Create role for homelab services
echo "🎭 Creating PKI role for services..."
VAULT_ADDR=$vault_addr VAULT_TOKEN=$VAULT_ROOT_TOKEN vault write pki_int/roles/service \
    issuer_ref="intermediate-ca" \
    allowed_domains="home,homelab.local" \
    allow_subdomains=true \
    allow_glob_domains=true \
    allow_wildcard_certificates=true \
    max_ttl=720h \
    ttl=720h \
    generate_lease=true

echo "✅ Service role created"

# Step 6: Test certificate generation
echo "🧪 Testing certificate generation..."
set -l test_cert (VAULT_ADDR=$vault_addr VAULT_TOKEN=$VAULT_ROOT_TOKEN vault write -format=json \
    pki_int/issue/service \
    common_name="*.home" \
    ttl=720h | jq -r '.data.certificate')

if test -z "$test_cert"
    echo "❌ Failed to generate test certificate"
    exit 1
end

echo "✅ Test certificate generated successfully"

# Display CA chain for download
echo ""
echo "📋 Root CA certificate available at:"
echo "   $vault_addr/v1/pki/ca/pem"
echo ""
echo "📋 Intermediate CA certificate available at:"
echo "   $vault_addr/v1/pki_int/ca/pem"
echo ""
echo "🎉 PKI setup complete!"
echo ""
echo "To trust these certificates, download the root CA and add to your system trust store:"
echo "   curl -o ~/homelab-root-ca.crt $vault_addr/v1/pki/ca/pem"
