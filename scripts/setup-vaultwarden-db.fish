#!/usr/bin/env fish

# Setup Vaultwarden database credentials in Vault and PostgreSQL

set -x VAULT_ADDR http://10.0.0.30:8200
set -x NOMAD_ADDR http://10.0.0.50:4646

echo "==> Creating Vaultwarden database password in Vault..."
set vw_password "vw_"(openssl rand -hex 16)
vault kv put secret/postgres/vaultwarden password=$vw_password
echo "Password created and stored in Vault"

echo ""
echo "==> Restarting PostgreSQL to run database initialization..."
nomad job stop -address=$NOMAD_ADDR postgresql
sleep 5
nomad job run -address=$NOMAD_ADDR jobs/services/postgresql.nomad.hcl

echo ""
echo "==> Waiting for PostgreSQL to start..."
sleep 20

echo ""
echo "==> Checking if vaultwarden database was created..."
set postgres_alloc (nomad job status -address=$NOMAD_ADDR postgresql -json | python3 -c "import sys, json; j = json.load(sys.stdin); allocs = j.get('Allocations', []); running = [a for a in allocs if a.get('ClientStatus') == 'running']; print(running[0]['ID'] if running else '')")

if test -n "$postgres_alloc"
    echo "PostgreSQL allocation: $postgres_alloc"
    echo "Checking databases..."
    nomad alloc exec -address=$NOMAD_ADDR $postgres_alloc psql -U postgres -c "\\l" | grep vaultwarden
else
    echo "ERROR: PostgreSQL is not running"
    exit 1
end

echo ""
echo "==> Deploying Vaultwarden..."
nomad job run -address=$NOMAD_ADDR jobs/services/vaultwarden.nomad.hcl

echo ""
echo "==> Done! Monitoring Vaultwarden deployment..."
sleep 10
nomad job status -address=$NOMAD_ADDR vaultwarden
