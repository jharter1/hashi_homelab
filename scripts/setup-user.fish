#!/usr/bin/env fish
# Setup a user in Vault with OIDC identity

set -l vault_addr "http://10.0.0.30:8200"
set -l username $argv[1]
set -l password $argv[2]
set -l email $argv[3]

if test (count $argv) -lt 3
    echo "Usage: setup-user.fish <username> <password> <email>"
    echo "Example: setup-user.fish jacques mypassword jacques@homelab.local"
    exit 1
end

# Source credentials
if test -f ~/.vault-hub-credentials
    source ~/.vault-hub-credentials
else if test -f ansible/.vault-hub-credentials
    source ansible/.vault-hub-credentials
else
    echo "Error: Vault credentials not found"
    exit 1
end

echo "Creating user: $username"

# Create user in userpass backend
VAULT_ADDR=$vault_addr VAULT_TOKEN=$VAULT_ROOT_TOKEN vault write auth/userpass/users/$username \
    password=$password \
    policies="default,nomad-workloads"

# Create identity entity
set -l entity_id (VAULT_ADDR=$vault_addr VAULT_TOKEN=$VAULT_ROOT_TOKEN vault write -format=json \
    identity/entity \
    name=$username \
    metadata=email=$email | jq -r '.data.id')

echo "Created entity: $entity_id"

# Get userpass accessor
set -l accessor (VAULT_ADDR=$vault_addr VAULT_TOKEN=$VAULT_ROOT_TOKEN vault auth list -format=json | jq -r '.["userpass/"].accessor')

# Create entity alias linking userpass to entity
VAULT_ADDR=$vault_addr VAULT_TOKEN=$VAULT_ROOT_TOKEN vault write identity/entity-alias \
    name=$username \
    canonical_id=$entity_id \
    mount_accessor=$accessor

# Add entity to homelab-users group
set -l group_id (VAULT_ADDR=$vault_addr VAULT_TOKEN=$VAULT_ROOT_TOKEN vault read -format=json \
    identity/group/name/homelab-users | jq -r '.data.id')

if test -n "$group_id"
    VAULT_ADDR=$vault_addr VAULT_TOKEN=$VAULT_ROOT_TOKEN vault write identity/group/id/$group_id \
        member_entity_ids=$entity_id
    echo "Added user to homelab-users group"
end

echo "✅ User $username created successfully!"
echo "   Email: $email"
echo "   Policies: default, nomad-workloads"
