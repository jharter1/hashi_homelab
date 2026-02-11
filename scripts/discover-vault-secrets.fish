#!/usr/bin/env fish
# Discover existing Vault secrets and generate Terraform import commands

set -x

# Colors
set green (set_color green)
set yellow (set_color yellow)
set blue (set_color blue)
set normal (set_color normal)

echo "$green"
echo "🔍 Discovering Vault Secrets"
echo "============================$normal"
echo ""

# Check if credentials are loaded
if not set -q VAULT_TOKEN
    echo "$yellow⚠️  VAULT_TOKEN not set. Run: source .credentials$normal"
    exit 1
end

echo "$blue► Checking postgres secrets...$normal"
set postgres_secrets (vault kv list -format=json secret/postgres/ 2>/dev/null | jq -r '.[]' 2>/dev/null)
if test -n "$postgres_secrets"
    echo "Found PostgreSQL secrets:"
    for secret in $postgres_secrets
        echo "  - postgres/$secret"
    end
else
    echo "  No postgres secrets found"
end

echo ""
echo "$blue► Checking mariadb secrets...$normal"
set mariadb_secrets (vault kv list -format=json secret/mariadb/ 2>/dev/null | jq -r '.[]' 2>/dev/null)
if test -n "$mariadb_secrets"
    echo "Found MariaDB secrets:"
    for secret in $mariadb_secrets
        echo "  - mariadb/$secret"
    end
else
    echo "  No mariadb secrets found"
end

echo ""
echo "$blue► Checking other secret paths...$normal"
set top_level (vault kv list -format=json secret/ 2>/dev/null | jq -r '.[]' 2>/dev/null)
if test -n "$top_level"
    echo "Top-level secret paths:"
    for path in $top_level
        echo "  - $path"
    end
end

echo ""
echo "$green✅ Discovery complete!$normal"
echo ""
echo "$yellow► Next steps:$normal"
echo "1. Review the secrets listed above"
echo "2. Update terraform/modules/vault-config/kv.tf with vault_kv_secret_v2 resources"
echo "3. Run terraform import for each existing secret"
echo ""
