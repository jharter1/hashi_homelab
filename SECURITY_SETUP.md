# Security Setup Guide

This guide helps you secure your homelab credentials and prevent accidental exposure.

## Quick Setup

1. **Create your credentials file**:
   ```bash
   cp .credentials.example .credentials
   nano .credentials  # Fill in your actual values
   ```

2. **Install pre-commit hook**:
   ```bash
   cp scripts/pre-commit.sh .git/hooks/pre-commit
   chmod +x .git/hooks/pre-commit
   ```

3. **Source credentials before running scripts**:
   ```fish
   source .credentials
   ```

## What's Protected

The following files and patterns are automatically ignored:

- **Credentials**: `.credentials`, `*credentials*` (except examples)
- **Vault files**: `ansible/.vault-*-credentials`, `.vault-tokens`
- **Terraform state**: `*.tfstate`, `*.tfstate.*`
- **AWS credentials**: `.aws/`, `*aws*credentials*`
- **Sensitive docs**: `SENSITIVE_INFO_ACTUAL.md`

## Using Credentials

### For Fish Scripts

All Fish scripts now check for environment variables:

```fish
source .credentials

# Run your scripts
./scripts/fix-vault-policy.fish
./scripts/setup-jwt-auth.fish
```

### For Ansible Playbooks

Ansible playbooks pull from environment variables:

```bash
source .credentials

cd ansible
ansible-playbook playbooks/configure-vault-jwt-auth.yml
```

### For Terraform

Use environment variables:

```bash
source .credentials

cd terraform/aws
terraform plan
terraform apply
```

## Security Best Practices

1. ✅ **Never commit** `.credentials` or any file with real tokens
2. ✅ **Always use** `.credentials.example` as templates
3. ✅ **Store application secrets** in Vault KV store
4. ✅ **Rotate credentials** if exposed
5. ✅ **Use short-lived tokens** with auto-renewal
6. ✅ **Review changes** before committing

## Pre-Commit Hook

The pre-commit hook automatically checks for:

- Sensitive file patterns (`.tfstate`, `.credentials`, etc.)
- Vault tokens (`hvs.*`)
- AWS access keys (`AKIA*`)
- Hardcoded passwords

If detected, the commit will be blocked with an error message.

## Historical Credentials

See [SENSITIVE_INFO.md](SENSITIVE_INFO.md) for a record of:

- Revoked/rotated credentials
- When they were exposed
- Recovery commands

## If Credentials Are Exposed

1. **Immediately rotate the credential**:
   - Vault: Generate new root token
   - AWS: Delete and recreate access keys
   - Passwords: Change and update in Vault

2. **Revoke the old credential**:
   ```bash
   # Vault token
   vault token revoke hvs.OLD_TOKEN
   
   # AWS key (in AWS Console)
   # Delete the old access key
   ```

3. **Update all references**:
   - `.credentials` file
   - Vault KV store
   - Nomad variables
   - Ansible variables

4. **Clean git history** (if committed):
   ```bash
   # Use BFG Repo-Cleaner or git-filter-repo
   git filter-repo --path path/to/sensitive/file --invert-paths
   git push origin --force --all
   ```

## Checking for Exposed Secrets

Run these commands to audit your repository:

```bash
# Check for patterns in git history
git log --all --full-history --source --remotes -- "*.tfstate"

# Use gitleaks for deep scan
docker run --rm -v $(pwd):/repo zricethezav/gitleaks:latest detect --source /repo

# Manual grep for tokens
git grep -E 'hvs\.|AKIA|password.*=.*["\']'
```

## Reference

- AWS credentials: Store in `secret/aws/traefik` in Vault
- Vault tokens: Keep in `.credentials`, never commit
- Database passwords: Always in Vault at `secret/postgres/*`
- Nomad variables: Use `nomad var put` for service credentials

---
*Last Updated: 2026-02-05*
