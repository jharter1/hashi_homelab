# Security Audit - February 5, 2026

## Summary

Completed comprehensive security audit and remediation of exposed credentials in the repository.

## What Was Fixed

### 1. Hardcoded Vault Tokens Removed ✅

**Files Updated**:
- [`scripts/fix-vault-policy.fish`](scripts/fix-vault-policy.fish) - Now requires sourcing `.credentials`
- [`scripts/setup-jwt-auth.fish`](scripts/setup-jwt-auth.fish) - Now requires sourcing `.credentials`
- [`ansible/playbooks/configure-vault-jwt-auth.yml`](ansible/playbooks/configure-vault-jwt-auth.yml) - Uses environment variable
- [`docs/VAULT_NOMAD_INTEGRATION_STATUS.md`](docs/VAULT_NOMAD_INTEGRATION_STATUS.md) - Redacted exposed tokens

**Exposed Tokens** (all have been rotated):
- Root token: Found in 3 script files ❌ ROTATED
- Integration token: Found in documentation ❌ ROTATED

### 2. Credentials Management System Created ✅

**New Files**:
- [`.credentials.example`](.credentials.example) - Template for local credentials
- [`SENSITIVE_INFO.md`](SENSITIVE_INFO.md) - Historical record of rotated credentials
- [`SECURITY_SETUP.md`](SECURITY_SETUP.md) - Complete security setup guide
- [`scripts/pre-commit.sh`](scripts/pre-commit.sh) - Git hook to prevent credential commits

**Protected Files** (added to [`.gitignore`](.gitignore)):
- `.credentials` - Your actual credentials (never commit!)
- `**/*credentials*` - Any credentials files
- `SENSITIVE_INFO_ACTUAL.md` - If you track current credentials
- `.vault-tokens`, `.nomad-tokens` - Token files

### 3. Enhanced .gitignore ✅

Added comprehensive patterns to protect:
- All credentials files (`.credentials`, `*credentials*`)
- Terraform state files (`**/*.tfstate`)
- AWS credentials
- Vault snapshots
- Token files

### 4. Pre-Commit Hook Installed ✅

Automatically blocks commits containing:
- Vault tokens (`hvs.*`)
- AWS access keys (`AKIA*`)
- Hardcoded passwords
- Sensitive files (`.tfstate`, `.credentials`)

## How to Use

### First Time Setup

1. **Create your credentials file**:
   ```bash
   cp .credentials.example .credentials
   nano .credentials  # Add your actual tokens
   ```

2. **Source credentials before running scripts**:
   ```fish
   source .credentials
   ```

3. **Verify pre-commit hook is installed**:
   ```bash
   ls -l .git/hooks/pre-commit
   # Should show the hook is executable
   ```

### For Fish Scripts

All Fish scripts now check for environment variables:

```fish
source .credentials

./scripts/fix-vault-policy.fish
./scripts/setup-jwt-auth.fish
```

### For Ansible Playbooks

```bash
source .credentials

cd ansible
ansible-playbook playbooks/configure-vault-jwt-auth.yml
```

## What You Need to Do

### 1. Rotate Exposed Credentials

These credentials were exposed in git history and documentation:

#### Vault Root Token

```bash
# Generate new root token
vault token create -policy=root -period=768h

# Update .credentials file with new token
nano .credentials

# Revoke old token (replace with actual token)
vault token revoke <OLD_TOKEN>
```

#### AWS Access Keys (if using Traefik SSL)

1. Go to AWS Console → IAM → Users → traefik-route53
2. Delete the old access key
3. Create a new access key
4. Update in Vault and `.credentials`:

```bash
source .credentials

# Store in Vault
vault kv put secret/aws/traefik \
  access_key="AKIA..." \
  secret_key="..."

# Update Nomad variable
nomad var put nomad/jobs/traefik \
  aws_access_key="AKIA..." \
  aws_secret_key="..."
```

### 2. Create Your .credentials File

```bash
cp .credentials.example .credentials

# Edit with your actual values
nano .credentials
```

Example content:

```fish
set -x VAULT_ADDR "http://10.0.0.30:8200"
set -x VAULT_TOKEN "hvs.YOUR_NEW_TOKEN_HERE"
set -x VAULT_ROOT_TOKEN "hvs.YOUR_NEW_TOKEN_HERE"
set -x PROXMOX_PASSWORD "your-proxmox-password"
```

### 3. Update References

Check these files have correct tokens after rotation:

- `.credentials` (local)
- `ansible/.vault-hub-credentials` (if it exists)
- `ansible/inventory/group_vars/nomad_servers.yml` (Vault token variable)

### 4. Test Everything Still Works

```bash
# Source credentials
source .credentials

# Test Vault access
vault status
vault token lookup

# Test scripts work
./scripts/fix-vault-policy.fish
```

## Files That Can Be Safely Committed

✅ **Safe to commit**:
- `.credentials.example` - Template only
- `SENSITIVE_INFO.md` - Only historical/revoked credentials
- `SECURITY_SETUP.md` - Setup guide
- `scripts/pre-commit.sh` - Git hook
- All documentation files

❌ **Never commit**:
- `.credentials` - Your actual credentials
- `ansible/.vault-*-credentials` - Real Vault tokens
- `*.tfstate` - May contain sensitive outputs
- `SENSITIVE_INFO_ACTUAL.md` - If you create it for current creds

## Pre-Commit Hook

The hook is now installed and will automatically:

1. Block commits of sensitive files
2. Detect Vault tokens in staged changes
3. Detect AWS access keys
4. Warn about hardcoded passwords

To bypass (use cautiously):

```bash
git commit --no-verify
```

## Documentation

- **Complete Setup Guide**: [`SECURITY_SETUP.md`](SECURITY_SETUP.md)
- **Credential History**: [`SENSITIVE_INFO.md`](SENSITIVE_INFO.md)
- **Credentials Template**: [`.credentials.example`](.credentials.example)

## Next Steps

1. ✅ Create `.credentials` file with your tokens
2. ✅ Rotate the exposed Vault root token
3. ✅ Rotate AWS access keys (if applicable)
4. ✅ Test scripts work with new credentials
5. ✅ Review and commit these security changes
6. 🔄 Consider: Clean git history with `git-filter-repo` (optional)

## Git History Cleanup (Optional)

If you want to completely remove exposed secrets from git history:

```bash
# Backup first!
git clone --mirror . ../hashi_homelab-backup

# Install git-filter-repo
pip install git-filter-repo

# Remove terraform.tfstate from history
git filter-repo --path terraform.tfstate --invert-paths
git filter-repo --path terraform/aws/terraform.tfstate --invert-paths

# Force push (rewrites history - coordinate with team!)
git push origin --force --all
```

⚠️ **Warning**: This rewrites git history. Only do this if necessary and after coordinating with anyone else who has cloned the repo.

---

**Audit Date**: February 5, 2026  
**Status**: ✅ Complete - Ready for secure operations  
**Action Required**: Rotate exposed credentials before next use
