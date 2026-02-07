#!/usr/bin/env fish
# Deploy Authelia SSO - Complete Setup Script

echo "🔐 Authelia SSO Deployment"
echo "=========================="
echo ""

# Step 1: Setup secrets
echo "Step 1: Generating and storing secrets in Vault..."
./scripts/setup-authelia-secrets.fish
if test $status -ne 0
    echo "❌ Failed to setup secrets"
    exit 1
end
echo ""

# Step 2: Generate password
echo "Step 2: Generate your password hash"
echo "    Run: ./scripts/generate-authelia-password.fish"
echo "    Then update jobs/services/authelia.nomad.hcl with the hash"
echo ""
echo "⚠️  IMPORTANT: Update the password hash in authelia.nomad.hcl before continuing!"
echo ""
read -P "Have you updated the password hash? (y/N): " confirm

if test "$confirm" != "y" -a "$confirm" != "Y"
    echo "❌ Please update the password hash first"
    exit 1
end

# Step 3: Deploy Redis
echo ""
echo "Step 3: Deploying Redis for session storage..."
nomad job run jobs/services/redis.nomad.hcl
if test $status -eq 0
    echo "✅ Redis deployed"
else
    echo "❌ Redis deployment failed"
    exit 1
end

# Wait for Redis to be healthy
echo "Waiting for Redis to be healthy..."
sleep 5

# Step 4: Deploy Authelia
echo ""
echo "Step 4: Deploying Authelia..."
nomad job run jobs/services/authelia.nomad.hcl
if test $status -eq 0
    echo "✅ Authelia deployed"
else
    echo "❌ Authelia deployment failed"
    exit 1
end

# Wait for Authelia to be healthy
echo "Waiting for Authelia to start..."
sleep 10

# Step 5: Verify deployment
echo ""
echo "Step 5: Verifying deployment..."
echo -n "Checking Authelia health... "
set status_code (curl -s -o /dev/null -w "%{http_code}" https://authelia.lab.hartr.net/api/health)

if test $status_code -eq 200
    echo "✅ Healthy"
else
    echo "❌ Not healthy (status: $status_code)"
    echo ""
    echo "Check logs with:"
    echo "  nomad job status authelia"
    echo "  nomad alloc logs -f (nomad job allocs authelia | grep running | awk '{print \$1}' | head -1)"
    exit 1
end

# Success!
echo ""
echo "✅ Authelia SSO Successfully Deployed!"
echo ""
echo "📋 Next Steps:"
echo "   1. Test login: https://authelia.lab.hartr.net"
echo "   2. Protect services by adding middleware tag:"
echo "      \"traefik.http.routers.SERVICE.middlewares=authelia@consulcatalog\""
echo "   3. Test protection: ./scripts/test-authelia-protection.fish"
echo ""
echo "📖 See docs/AUTHELIA_PROTECTION_EXAMPLES.md for examples"
