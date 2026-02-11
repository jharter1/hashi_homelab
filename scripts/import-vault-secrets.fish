#!/usr/bin/env fish
# Import existing Vault secrets into Terraform state

set -x

# Colors
set green (set_color green)
set yellow (set_color yellow)
set red (set_color red)
set normal (set_color normal)

echo "$green"
echo "🔐 Importing Existing Vault Secrets to Terraform"
echo "================================================$normal"
echo ""

# Check if we're in the right directory
if not test -f "Taskfile.yml"
    echo "$red❌ Error: Run this script from the project root$normal"
    exit 1
end

# Navigate to terraform/environments/dev
cd terraform/environments/dev

echo "$yellow► Importing PostgreSQL secrets...$normal"

# PostgreSQL secrets
terraform import 'module.vault_config.vault_kv_secret_v2.postgres_admin' 'secret/data/postgres/admin'
terraform import 'module.vault_config.vault_kv_secret_v2.postgres_authelia' 'secret/data/postgres/authelia'
terraform import 'module.vault_config.vault_kv_secret_v2.postgres_freshrss' 'secret/data/postgres/freshrss'
terraform import 'module.vault_config.vault_kv_secret_v2.postgres_gitea' 'secret/data/postgres/gitea'
terraform import 'module.vault_config.vault_kv_secret_v2.postgres_grafana' 'secret/data/postgres/grafana'
terraform import 'module.vault_config.vault_kv_secret_v2.postgres_speedtest' 'secret/data/postgres/speedtest'
terraform import 'module.vault_config.vault_kv_secret_v2.postgres_uptimekuma' 'secret/data/postgres/uptimekuma'
terraform import 'module.vault_config.vault_kv_secret_v2.postgres_vaultwarden' 'secret/data/postgres/vaultwarden'

echo ""
echo "$yellow► Importing MariaDB secrets...$normal"

# MariaDB secrets
terraform import 'module.vault_config.vault_kv_secret_v2.mariadb_admin' 'secret/data/mariadb/admin'
terraform import 'module.vault_config.vault_kv_secret_v2.mariadb_seafile' 'secret/data/mariadb/seafile'

echo ""
echo "$green✅ Import complete!$normal"
echo ""
echo "$yellow⚠️  Important: The ignore_changes lifecycle means Terraform won't overwrite your existing passwords.$normal"
echo "$yellow   To apply the updated policy, run:$normal"
echo ""
echo "   cd terraform/environments/dev"
echo "   terraform apply"
echo ""
