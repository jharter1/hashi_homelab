# Sensitive Information - Reference Only

> ⚠️ **WARNING**: Never commit actual credentials to this repository.  
> All credentials should ONLY be stored in `.credentials` (gitignored) or Vault.

## Credential Storage Locations

### Vault Tokens
- **Root Token**: Store in `.credentials` file (never commit!)
- **Integration Tokens**: Generated as needed, store in `.credentials`

### AWS Credentials
- **Location**: Stored in Vault at `secret/aws/traefik`
- **Nomad Access**: Via Nomad variables (see Traefik job)
- **Rotation**: Delete old key in AWS Console, create new, update Vault

## Where to Store Current Credentials

All current credentials should be stored in:
- **`.credentials`** - Fish shell environment file (gitignored)
- **`ansible/.vault-hub-credentials`** - Vault credentials for Ansible (gitignored)
- **Vault KV Store** - For application secrets accessed by Nomad jobs

### Loading Credentials

```fish
# Source credentials
source .credentials

# Verify
echo $VAULT_TOKEN
```

## Credential Rotation History

| Date | Action | Credential Type | Reason |
|------|--------|----------------|--------|
| 2026-02-05 | Rotated | Vault Root Token | Exposed in git history |
| 2026-02-05 | Rotated | AWS Access Keys | Exposed in terraform.tfstate |
| 2026-02-05 | Revoked | Nomad-Vault Token | Exposed in docs |

## Security Best Practices

1. ✅ Never commit `.credentials` or any file with real tokens
2. ✅ Use `.credentials.example` as a template
3. ✅ Store sensitive values in Vault KV store when possible
4. ✅ Rotate tokens immediately if exposed
5. ✅ Use short-lived tokens with auto-renewal
6. ✅ Review git history before pushing
7. ✅ Enable pre-commit hooks to catch secrets

## Recovery Commands

If you need to regenerate the root token:

```bash
# Using unseal keys
vault operator generate-root -init

# Or create a new token from existing root token
vault token create -policy=root -period=768h
```

If AWS keys are exposed:

```bash
# 1. Delete old key in AWS Console
# 2. Create new key
# 3. Update in Vault
vault kv put secret/aws/traefik \
  access_key="AKIA..." \
  secret_key="..."
  
# 4. Update Nomad variable
nomad var put nomad/jobs/traefik \
  aws_access_key="AKIA..." \
  aws_secret_key="..."
```

---
*Last Updated: 2026-02-05*
