# Configuration Externalization Status

This document tracks which service configurations have been externalized to `/configs` and which must remain as Nomad template blocks.

## ✅ Externalized Configs (Static)

These configurations contain no secrets or dynamic service discovery and have been moved to `/configs/`:

### Infrastructure
- **Traefik** (`configs/infrastructure/traefik/traefik.yml`)
  - Static routing configuration
  - Entrypoints, providers, Let's Encrypt settings
  - ⚠️ Dynamic config (Authelia middleware) stays templated for Consul SD

### Observability
- **Prometheus** (`configs/observability/prometheus/prometheus.yml`)
  - Scrape configs for static targets (Nomad servers/clients)
  - Consul SD configs (static structure)
  - Global settings and retention policies

- **Grafana**
  - Datasources: `configs/observability/grafana/datasources.yml`
  - Dashboards: `configs/observability/grafana/dashboards.yml`
  - ⚠️ Database password still injected via Vault template

- **Loki** (`configs/observability/loki/loki.yaml`)
  - Server configuration
  - Storage settings
  - Schema configuration
  - Limits and retention

- **Alertmanager** (`configs/observability/alertmanager/alertmanager.yml`)
  - Routing rules
  - Receiver definitions
  - Inhibit rules

## 🔒 Template-Only Configs (Dynamic/Secrets)

These configurations MUST remain as Nomad `template` blocks due to secrets or service discovery:

### System Services
- **Alloy** (`jobs/system/alloy.nomad.hcl`)
  - **Reason:** Uses Consul SD for Loki endpoint: `{{ range service "loki" }}`
  - **Pattern:** Dynamic service discovery
  - **Alternative:** Could use static DNS (loki.service.consul) but Consul template provides resilience

### Authentication
- **Authelia** (`jobs/services/auth/authelia/authelia.nomad.hcl`)
  - **Reason:** Multiple Vault secrets embedded:
    - `jwt_secret`
    - `session_secret`
    - `encryption_key`
    - PostgreSQL password
  - **Reason 2:** Consul SD for Redis and PostgreSQL endpoints
  - **Pattern:** Security-sensitive configuration with dynamic backends
  - **Lines:** ~150 lines of templated YAML with 4+ Vault lookups

### Databases
- **PostgreSQL** (`jobs/services/databases/postgresql/postgresql.nomad.hcl`)
  - **Reason:** Init script contains Vault passwords for services:
    - freshrss, gitea, authelia, vaultwarden, grafana, speedtest, etc.
  - **Pattern:** Database initialization with per-service secrets
  - **Lines:** ~200 lines of SQL with Vault interpolation

- **MariaDB** (`jobs/services/databases/mariadb/mariadb.nomad.hcl`)
  - **Reason:** Init script contains Vault passwords
  - **Pattern:** Same as PostgreSQL

## 📊 Statistics

### Phase 1 Progress
- **Externalized:** 5 services (Traefik, Prometheus, Grafana, Loki, Alertmanager)
- **Template-Only:** 4 services (Alloy, Authelia, PostgreSQL, MariaDB)
- **HCL Lines Reduced:** ~300 lines converted to external files
- **Remaining HEREDOC Services:** ~13 (see Phase 1 roadmap)

### Config Types
- **Static configs:** 7 files externalized
- **Vault-templated:** 4 services (acceptable pattern)
- **Consul SD:** 2 services (Alloy, Traefik dynamic)

## 🎯 Design Patterns

### Pattern 1: Full Externalization
**When to use:** Static configuration with no secrets or service discovery

```hcl
config {
  volumes = [
    "/mnt/nas/configs/service/config.yml:/etc/service/config.yml:ro",
  ]
}
```

**Examples:** Loki, Alertmanager, Prometheus (partially)

### Pattern 2: Hybrid (External + Secrets)
**When to use:** Config structure is static, but secrets need injection

```hcl
config {
  volumes = [
    "/mnt/nas/configs/service/config.yml:/etc/service/config.yml:ro",
  ]
}

template {
  destination = "secrets/db.env"
  env = true
  data = <<EOH
DB_PASSWORD={{ with secret "secret/data/postgres/service" }}{{ .Data.data.password }}{{ end }}
  EOH
}
```

**Examples:** Grafana (datasources external, DB password templated)

### Pattern 3: Full Template (Security/Dynamic)
**When to use:** Multiple secrets OR Consul service discovery required

```hcl
template {
  destination = "local/config.yml"
  data = <<EOH
# Config with embedded secrets and/or Consul SD
database:
  password: {{ with secret "..." }}{{ .Data.data.password }}{{ end }}
  host: {{ range service "postgres" }}{{ .Address }}{{ end }}
  EOH
}
```

**Examples:** Authelia, PostgreSQL init scripts, Alloy

## 🔐 Security Considerations

### Why Templates for Secrets?
1. **Never commit secrets to git:** Vault integration prevents plaintext passwords
2. **Dynamic secret rotation:** Vault can rotate secrets without config file changes
3. **Least privilege:** Nomad workload identity provides scoped access

### External Config Security
- All external configs are world-readable (mounted :ro)
- No secrets should ever be in `/configs/`
- Config files are version-controlled and auditable

## 📝 Adding New Services

### Decision Tree

**Does the config have secrets?**
- YES → Use template pattern (Pattern 2 or 3)
- NO → Continue

**Does the config use Consul service discovery?**
- YES → Use template for dynamic parts (Pattern 3)
- NO → Externalize fully (Pattern 1)

**Does the config change frequently?**
- YES → Consider template for flexibility
- NO → Externalize

### Checklist
- [ ] Identify secrets (passwords, tokens, keys)
- [ ] Identify dynamic parts (Consul SD, conditional logic)
- [ ] Choose pattern (1, 2, or 3)
- [ ] Extract static parts to `/configs/` if applicable
- [ ] Update Ansible `config-sync` role
- [ ] Add config sync task to Taskfile
- [ ] Document in this file

## 🚀 Deployment

### Syncing Configs
```fish
# Sync all externalized configs to cluster
task configs:sync

# Validate configs before deploying
task configs:validate:all
```

### Service Restart After Config Changes
Ansible handlers automatically restart affected services when configs change. Manual restart:

```fish
nomad job restart SERVICE-NAME
```

### Rollback Strategy
```fish
# Revert config changes in git
git checkout HEAD~1 configs/service/config.yml

# Re-sync
task configs:sync

# Restart service
nomad job restart SERVICE-NAME
```

## 🔮 Future Enhancements

### Potential Improvements
1. **Config validation in CI:** Pre-merge validation of all YAML/HCL syntax
2. **Checksums in metadata:** Track config versions in Nomad job metadata
3. **Nomad Packs:** Convert patterns to reusable pack templates
4. **Consul KV for dynamic configs:** Store frequently-changing configs in Consul
5. **Automated testing:** Deploy to test namespace before production

### Services to Externalize Next
See [../REFACTOR_PROGRESS.md](../REFACTOR_PROGRESS.md) for Phase 1 remaining items.

---

**Last Updated:** February 11, 2026  
**Total Configs Externalized:** 7 files across 5 services  
**Template-Only Services:** 4 (security/dynamic requirements)
