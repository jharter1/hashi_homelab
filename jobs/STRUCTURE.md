# Jobs Directory Structure

```
jobs/
├── services/
│   ├── _patterns/
│   │   └── README.md                    # Pattern documentation
│   │
│   ├── observability/                   # Monitoring & Observability Stack
│   │   ├── prometheus/
│   │   │   ├── prometheus.nomad.hcl
│   │   │   └── prometheus.yml
│   │   ├── grafana/
│   │   │   ├── grafana.nomad.hcl
│   │   │   └── dashboards/
│   │   │       └── nomad-cluster.json
│   │   ├── loki/
│   │   │   └── loki.nomad.hcl
│   │   ├── alertmanager/
│   │   │   └── alertmanager.nomad.hcl
│   │   └── uptime-kuma/
│   │       └── uptime-kuma.nomad.hcl
│   │
│   ├── databases/                       # Data Stores
│   │   ├── postgresql/
│   │   │   └── postgresql.nomad.hcl    # Centralized, used by 14+ services
│   │   └── mariadb/
│   │       └── mariadb.nomad.hcl       # Legacy, Seafile only
│   │
│   ├── auth/                            # Authentication & Security
│   │   ├── authelia/
│   │   │   └── authelia.nomad.hcl      # SSO provider
│   │   ├── redis/
│   │   │   └── redis.nomad.hcl         # Authelia session store
│   │   └── vaultwarden/
│   │       └── vaultwarden.nomad.hcl   # Password manager
│   │
│   ├── media/                           # Content & Media Services
│   │   ├── freshrss/
│   │   │   └── freshrss.nomad.hcl      # RSS reader
│   │   ├── calibre/
│   │   │   └── calibre.nomad.hcl       # eBook library
│   │   ├── audiobookshelf/
│   │   │   └── audiobookshelf.nomad.hcl
│   │   └── seafile/
│   │       └── seafile.nomad.hcl       # File sync & share
│   │
│   ├── development/                     # Developer Tools
│   │   ├── gitea/
│   │   │   └── gitea.nomad.hcl         # Git hosting
│   │   ├── gollum/
│   │   │   └── gollum.nomad.hcl        # Wiki
│   │   ├── codeserver/
│   │   │   └── codeserver.nomad.hcl    # VS Code in browser
│   │   └── docker-registry/
│   │       └── docker-registry.nomad.hcl  # Private Docker registry + UI
│   │
│   └── infrastructure/                  # Core Infrastructure
│       ├── minio/
│       │   └── minio.nomad.hcl         # S3-compatible object storage
│       ├── homepage/
│       │   └── homepage.nomad.hcl      # Dashboard
│       ├── speedtest/
│       │   └── speedtest.nomad.hcl     # Speedtest Tracker
│       └── whoami/
│           └── whoami.nomad.hcl        # Testing service
│
├── system/                              # System Jobs (run on all/most clients)
│   ├── traefik.nomad.hcl               # Reverse proxy
│   └── grafana-alloy.nomad.hcl         # Metrics collector
│
└── test/                                # Test & Development Jobs
    └── test-vault-integration.nomad.hcl
```

## Quick Reference

**Total Services:** 22 production services  
**Categories:** 6 functional groupings  
**Patterns:** 3 documented architectural patterns  

**Deployment:**
```bash
# Deploy by category
task deploy:services              # Core monitoring stack
task deploy:speedtest            # Individual service
task deploy:all                  # Everything (system + services)

# Deploy specific service
nomad job run jobs/services/observability/grafana/grafana.nomad.hcl

# Validate before deploy
nomad job validate jobs/services/auth/authelia/authelia.nomad.hcl
```

**Service Access:**
All services available at `https://SERVICE.lab.hartr.net` with Authelia SSO (except monitoring stack at `.home`)

**Port Allocations:**
See [`docs/CHEATSHEET.md`](../../docs/CHEATSHEET.md#nomad-service-ports) for complete port map

## Migration Notes (2026-02-11)

✅ Migrated from flat structure to organized hierarchy  
✅ All Taskfile.yml paths updated  
✅ Pattern documentation created  
✅ Prometheus config preserved in service directory  
✅ Grafana dashboards moved to service directory  

**Future Services:**
- Reserve directory for immich in `media/immich/` (referenced in Taskfile)
