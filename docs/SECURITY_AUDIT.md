# Security Audit Report
Date: December 10, 2025

## Executive Summary
Security audit completed on the hashi_homelab repository to identify hardcoded secrets and credentials.

## Findings

### Critical Issues

#### 1. Terraform Vault Configuration - Placeholder Secrets
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

#### 2. Proxmox VM Default Password
**File:** `terraform/modules/proxmox-vm/main.tf:84`  
**Severity:** MEDIUM  
**Status:** ACCEPTABLE (with documentation)

**Issue:** Default password `ubuntu` set for cloud-init

**Recommendation:** This is acceptable for cloud-init as it requires manual password change on first login. Document this in deployment guide.

### Low-Risk Findings

#### 3. Packer Build Passwords
**Files:** Multiple packer templates  
**Value:** `ssh_password = "packer"`  
**Severity:** LOW  
**Status:** ACCEPTABLE

**Rationale:** These are temporary build-time credentials for image creation only. Not used in production systems.

#### 4. Documentation Examples
**Files:** README.md, install-vault.yml  
**Status:** ACCEPTABLE

These are placeholder examples in documentation showing proper format.

## Completed Mitigations

✅ **Grafana:** Migrated to Vault-backed credentials with random password  
✅ **MinIO:** Migrated to Vault-backed credentials with random password  
✅ **Nomad Job Files:** Clean - no hardcoded secrets found

## Action Items

### Immediate (Priority 1)

1. **Update Terraform vault-config**
   ```bash
   # Generate random values
   docker_registry_password=$(openssl rand -base64 32)
   prometheus_password=$(openssl rand -base64 32)
   consul_gossip_key=$(consul keygen)
   
   # Update Terraform or delete Terraform-managed secrets and manage manually
   ```

2. **Docker Registry Credentials**
   - Currently has placeholder in Terraform
   - Need to decide: use Docker Registry or remove job
   - If keeping: generate secure credentials and update job

3. **Prometheus Credentials**
   - Generate secure password in Vault
   - Add vault integration to prometheus job if needed

4. **Consul Gossip Encryption**
   - Generate proper gossip key: `consul keygen`
   - Update Vault secret
   - Configure Consul to use encrypted gossip

### Medium Priority

5. **Terraform State Security**
   - Ensure terraform.tfstate is in .gitignore
   - Consider remote backend (S3 + DynamoDB, or Consul)
   - Enable state encryption

6. **Git History Cleanup**
   - Review git history for any accidentally committed secrets
   - Use tools like `gitleaks` or `truffleHog` for deep scan
   - Consider `git-filter-repo` if secrets found in history

### Long-term

7. **Secrets Management Policy**
   - Document that all secrets MUST go in Vault
   - Add pre-commit hooks to prevent secret commits
   - Regular security audits (quarterly)

8. **Access Control**
   - Review Vault policies regularly
   - Implement least-privilege access
   - Rotate root tokens
   - Enable Vault audit logging

## Scan Methodology

### Tools Used
- `grep` with regex patterns for common secret formats
- Manual code review of configuration files
- Pattern matching for: `password=`, `token=`, `secret=`, `api_key=`, `changeme`

### Files Scanned
- All `.hcl` files (Nomad jobs, Packer templates)
- All `.tf` files (Terraform configurations)
- All `.yml`/`.yaml` files (Ansible playbooks)
- Documentation files (README.md)

### Patterns Searched
```regex
(password|token|secret|api_key|apikey)\s*[=:]\s*["\']?[a-zA-Z0-9_\-\+\/=]{8,}
changeme
```

## Next Steps

1. ✅ Complete security scan
2. ⏳ Fix Terraform vault-config placeholder secrets
3. ⏳ Decide on Docker Registry usage
4. ⏳ Add Prometheus vault integration if needed
5. ⏳ Configure Consul gossip encryption
6. ⏳ Git history scan with gitleaks
7. ⏳ Add pre-commit hooks

## Recommendations Summary

**Immediate Actions:**
- Replace all "changeme" placeholders with secure random values
- Update Terraform or migrate to manual Vault management
- Enable Consul gossip encryption

**Security Posture:**
- Overall: GOOD (most services using Vault)
- Trajectory: IMPROVING (active vault integration)
- Remaining Risk: MEDIUM (Terraform placeholders need attention)
