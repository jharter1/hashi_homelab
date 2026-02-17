#!/usr/bin/env fish
# Complete Vault Setup Helper Script

set -x

# Colors
set green (set_color green)
set yellow (set_color yellow)
set red (set_color red)
set normal (set_color normal)

echo "$green"
echo "🔐 Vault Setup Automation"
echo "=========================$normal"
echo ""

# Check if we're in the right directory
if not test -f "Taskfile.yml"
    echo "$red❌ Error: Run this script from the project root$normal"
    exit 1
end

# Step 1: Install Vault via Ansible
echo "$yellow► Step 1: Installing Vault via Ansible...$normal"
cd ansible
ansible-playbook -i inventory/hosts.yml playbooks/install-vault.yml
cd ..

if not test -f "ansible/.vault-credentials"
    echo "$red❌ Error: Vault credentials file not created. Check Ansible output.$normal"
    exit 1
end

echo "$green✓ Vault installed and initialized$normal"
echo ""

# Step 2: Configure Vault with Terraform
echo "$yellow► Step 2: Configuring Vault with Terraform...$normal"

# Parse credentials file (bash format to fish variables)
set -x VAULT_UNSEAL_KEY (grep VAULT_UNSEAL_KEY ansible/.vault-credentials | cut -d= -f2)
set -x VAULT_ROOT_TOKEN (grep VAULT_ROOT_TOKEN ansible/.vault-credentials | cut -d= -f2)

# Override VAULT_ADDR to use actual server IP (not 127.0.0.1)
set -x VAULT_ADDR "http://10.0.0.50:8200"

# Set Vault provider environment variables
set -x VAULT_TOKEN $VAULT_ROOT_TOKEN

# Set Terraform variables
set -x TF_VAR_vault_token $VAULT_ROOT_TOKEN
set -x TF_VAR_vault_address $VAULT_ADDR

# Navigate to terraform directory
cd terraform/environments/dev

# Initialize (always, to ensure providers are up to date)
echo "Initializing Terraform..."
terraform init

# Apply Vault configuration
echo "Applying Vault configuration..."
terraform apply -target=module.vault_config -auto-approve

if test $status -eq 0
    echo ""
    echo "$green✅ Vault setup complete!$normal"
    echo ""
    echo "📋 Next steps:"
    echo ""
    echo "1. Get Nomad server token:"
    echo "   cd terraform/environments/dev"
    echo "   terraform output -raw nomad_server_token"
    echo ""
    echo "2. Save root CA certificate:"
    echo "   terraform output -raw root_ca_cert > ~/homelab-root-ca.crt"
    echo ""
    echo "3. Update Nomad configuration (see docs/VAULT.md)"
    echo ""
else
    echo "$red❌ Terraform apply failed$normal"
    exit 1
end
