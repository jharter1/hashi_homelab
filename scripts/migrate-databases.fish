#!/usr/bin/env fish
# Database Migration Deployment Script
# Migrates services from SQLite/embedded databases to centralized PostgreSQL

set -x NOMAD_ADDR "http://10.0.0.50:4646"
set -x VAULT_ADDR "http://10.0.0.30:8200"

echo "🗄️  Database Migration to Central PostgreSQL"
echo "=============================================="
echo ""

# Check prerequisites
echo "📋 Checking prerequisites..."
echo ""

# Check Vault is accessible
if not vault status > /dev/null 2>&1
    echo "❌ Vault is not accessible at $VAULT_ADDR"
    echo "   Please ensure Vault is running and you are authenticated"
    exit 1
end

# Check Nomad is accessible
if not nomad status > /dev/null 2>&1
    echo "❌ Nomad is not accessible at $NOMAD_ADDR"
    echo "   Please ensure Nomad is running"
    exit 1
end

# Check PostgreSQL service exists
if not nomad job status postgresql > /dev/null 2>&1
    echo "❌ PostgreSQL job not found"
    echo "   Please deploy PostgreSQL first: nomad job run jobs/services/postgresql.nomad.hcl"
    exit 1
end

echo "✅ Prerequisites check passed"
echo ""

# Confirm migration
echo "⚠️  WARNING: This will migrate the following services to PostgreSQL:"
echo "   - Immich (embedded PostgreSQL → central)"
echo "   - Speedtest Tracker (SQLite → PostgreSQL)"
echo "   - Uptime-Kuma (SQLite → PostgreSQL)"
echo "   - Vaultwarden (SQLite → PostgreSQL)"
echo ""
echo "📝 IMPORTANT:"
echo "   - Speedtest: Historical data will be LOST (fresh start)"
echo "   - Uptime-Kuma: Monitoring history will be LOST (fresh start)"
echo "   - Vaultwarden: CRITICAL - All passwords will be LOST unless exported first!"
echo "   - Immich: Photos are safe, but may lose AI search metadata"
echo ""
read -P "Have you backed up Vaultwarden data? (yes/no): " -l confirm

if test "$confirm" != "yes"
    echo "❌ Aborting. Please backup Vaultwarden first:"
    echo "   1. Access https://vaultwarden.lab.hartr.net"
    echo "   2. Export all vaults"
    echo "   3. Save export file securely"
    echo "   4. Re-run this script"
    exit 1
end

read -P "Continue with migration? (yes/no): " -l confirm

if test "$confirm" != "yes"
    echo "❌ Migration cancelled"
    exit 0
end

echo ""
echo "🚀 Starting migration..."
echo ""

# Step 1: Create Vault secrets
echo "Step 1/5: Creating Vault secrets for new databases..."
fish scripts/setup-db-migration-secrets.fish
if test $status -ne 0
    echo "❌ Failed to create Vault secrets"
    exit 1
end
echo ""

# Step 2: Redeploy PostgreSQL with new database initialization
echo "Step 2/5: Redeploying PostgreSQL with new databases..."
nomad job stop postgresql
sleep 5
nomad job run jobs/services/postgresql.nomad.hcl
if test $status -ne 0
    echo "❌ Failed to deploy PostgreSQL"
    exit 1
end

echo "   Waiting for PostgreSQL to initialize (30 seconds)..."
sleep 30
echo ""

# Step 3: Deploy migrated services
echo "Step 3/5: Deploying Immich..."
nomad job run jobs/services/immich.nomad.hcl
if test $status -ne 0
    echo "❌ Failed to deploy Immich"
    exit 1
end
sleep 5
echo ""

echo "Step 4/5: Deploying Speedtest Tracker..."
nomad job run jobs/services/speedtest.nomad.hcl
if test $status -ne 0
    echo "❌ Failed to deploy Speedtest"
    exit 1
end
sleep 5
echo ""

echo "Step 5/5: Deploying Uptime-Kuma and Vaultwarden..."
nomad job run jobs/services/uptime-kuma.nomad.hcl
if test $status -ne 0
    echo "❌ Failed to deploy Uptime-Kuma"
    exit 1
end

nomad job run jobs/services/vaultwarden.nomad.hcl
if test $status -ne 0
    echo "❌ Failed to deploy Vaultwarden"
    exit 1
end
echo ""

# Step 4: Verify deployments
echo "✅ All services deployed successfully!"
echo ""
echo "📊 Checking service status..."
echo ""

# Wait for allocations to start
sleep 10

# Check job statuses
echo "Nomad Job Statuses:"
nomad job status postgresql | grep -E "Status|Running"
nomad job status immich | grep -E "Status|Running"
nomad job status speedtest | grep -E "Status|Running"
nomad job status uptime-kuma | grep -E "Status|Running"
nomad job status vaultwarden | grep -E "Status|Running"
echo ""

echo "🎉 Migration deployment complete!"
echo ""
echo "📋 Next Steps:"
echo ""
echo "1. Verify service access:"
echo "   - Immich: https://immich.lab.hartr.net"
echo "   - Speedtest: https://speedtest.lab.hartr.net"
echo "   - Uptime-Kuma: https://uptime-kuma.lab.hartr.net"
echo "   - Vaultwarden: https://vaultwarden.lab.hartr.net"
echo ""
echo "2. For Vaultwarden:"
echo "   - Create new admin account"
echo "   - Import your exported vault data"
echo "   - Verify all passwords are accessible"
echo ""
echo "3. For Uptime-Kuma:"
echo "   - Create new admin account"
echo "   - Re-add monitoring endpoints"
echo "   - Configure status page"
echo ""
echo "4. For Speedtest:"
echo "   - Wait for scheduled runs (every 6 hours)"
echo "   - Or manually trigger tests in UI"
echo ""
echo "5. Monitor logs for any errors:"
echo "   nomad alloc logs -f \$(nomad job allocs immich -json | jq -r '.[0].ID')"
echo ""
echo "6. Check database sizes after 24 hours:"
echo "   psql -h postgresql.service.consul -U postgres -c \"SELECT datname, pg_size_pretty(pg_database_size(datname)) FROM pg_database WHERE datname IN ('immich', 'speedtest', 'uptimekuma', 'vaultwarden');\""
echo ""
echo "📖 See docs/POSTGRESQL.md for complete documentation"
