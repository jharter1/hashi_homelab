# Security Audit Report

---

## February 5, 2026 Audit - Credentials Exposure Remediation

### Summary

Completed comprehensive security audit and remediation of exposed credentials in the repository.

### What Was Fixed

#### 1. Hardcoded Vault Tokens Removed ✅

**Files Updated**:
- [`scripts/fix-vault-policy.fish`](../scripts/fix-vault-policy.fish) - Now requires sourcing `.credentials`
- [`scripts/setup-jwt-auth.fish`](../scripts/setup-jwt-auth.fish) - Now requires sourcing `.credentials`
- [`ansible/playbooks/configure-vault-jwt-auth.yml`](../ansible/playbooks/configure-vault-jwt-auth.yml) - Uses environment variable
- [`docs/VAULT.md`](VAULT.md) - Redacted exposed tokens

**Exposed Tokens** (all have been rotated):
- Root token: Found in 3 script files ❌ ROTATED
- Integration token: Found in documentation ❌ ROTATED

#### 2. Credentials Management System Created ✅

**New Files**:
- [`.credentials.example`](../.credentials.example) - Template for local credentials
- [`SENSITIVE_INFO.md`](../SENSITIVE_INFO.md) - Historical record of rotated credentials
- [`SECURITY_SETUP.md`](../SECURITY_SETUP.md) - Complete security setup guide
- [`scripts/pre-commit.sh`](../scripts/pre-commit.sh) - Git hook to prevent credential commits

**Protected Files** (added to [`.gitignore`](../.gitignore)):
- `.credentials` - Your actual credentials (never commit!)
- `**/*credentials*` - Any credentials files
- `SENSITIVE_INFO_ACTUAL.md` - If you track current credentials
- `.vault-tokens`, `.nomad-tokens` - Token files

#### 3. Enhanced .gitignore ✅

Added comprehensive patterns to protect:
- All credentials files (`.credentials`, `*credentials*`)
- Terraform state files (`**/*.tfstate`)
- AWS credentials
- Vault snapshots
- Token files

#### 4. Pre-Commit Hook Installed ✅

Automatically blocks commits containing:
- Vault tokens (`hvs.*`)
- AWS access keys (`AKIA*`)
- Hardcoded passwords
- Sensitive files (`.tfstate`, `.credentials`)

### How to Use

#### First Time Setup

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

#### For Fish Scripts

All Fish scripts now check for environment variables:

```fish
source .credentials

./scripts/fix-vault-policy.fish
./scripts/setup-jwt-auth.fish
```

#### For Ansible Playbooks

```bash
source .credentials

cd ansible
ansible-playbook playbooks/configure-vault-jwt-auth.yml
```

---

## December 10, 2025 Audit - Initial Security Scan

### Executive Summary
Security audit completed on the hashi_homelab repository to identify hardcoded secrets and credentials.

### Findings

#### Critical Issues

##### 1. Terraform Vault Configuration - Placeholder Secrets
**File:** `terraform/modules/vault-config/kv.tf`  
**Severity:** HIGH  
**Status:** NEEDS ATTENTION

**Issues Found:**
- Docker Registry credentials: `admin` / `changeme-please`
- Grafana credentials: `changeme-please` (already migrated to secure value)
- Prometheus credentials: `changeme-please`
- Consul gossip key: `changeme-use-consul-keygen`

**Impact:** These are Terraform-managed secrets. Currently using placeholder values that should be replaced.

**Recommendation:** 
- Generate secure random values for all secrets
- Use Terraform random provider or external data source
- Update Grafana and MinIO values (already done via manual vault kv put)
- Remove Terraform-managed secrets where already updated manually

##### 2. Proxmox VM Default Password
**File:** `terraform/modules/proxmox-vm/main.tf:84`  
**Severity:** MEDIUM  
**Status:** ACCEPTABLE (with documentation)

**Issue:** Default password `ubuntu` set for cloud-init

**Recommendation:** This is acceptable for cloud-init as it requires manual password change on first login. Document this in deployment guide.

#### Low-Risk Findings

##### 3. Packer Build Passwords
**Files:** Multiple packer templates  
**Value:** `ssh_password = "packer"`  
**Severity:** LOW  
**Status:** ACCEPTABLE

**Rationale:** These are temporary build-time credentials for image creation only. Not used in production systems.

##### 4. Documentation Examples
**Files:** README.md, install-vault.yml  
**Status:** ACCEPTABLE

These are placeholder examples in documentation showing proper format.

### Completed Mitigations

✅ **Grafana:** Migrated to Vault-backed credentials with random password  
✅ **MinIO:** Migrated to Vault-backed credentials with random password  
✅ **Nomad Job Files:** Clean - no hardcoded secrets found

### Scan Methodology

#### Tools Used
- `grep` with regex patterns for common secret formats
- Manual code review of configuration files
- Pattern matching for: `password=`, `token=`, `secret=`, `api_key=`, `changeme`

#### Files Scanned
- All `.hcl` files (Nomad jobs, Packer templates)
- All `.tf` files (Terraform configurations)
- All `.yml`/`.yaml` files (Ansible playbooks)
- Documentation files (README.md)

#### Patterns Searched
```regex
(password|token|secret|api_key|apikey)\s*[=:]\s*["\']?[a-zA-Z0-9_\-\+\/=]{8,}
changeme
```

### Recommendations Summary

**Security Posture:**
- Overall: GOOD (most services using Vault)
- Trajectory: IMPROVING (active vault integration)
- Remaining Risk: LOW (after Feb 2026 remediation)

---

**Latest Audit Date**: February 5, 2026  
**Status**: ✅ Complete - Secure operations enabled  
**For Setup**: See [`SECURITY_SETUP.md`](../SECURITY_SETUP.md)
