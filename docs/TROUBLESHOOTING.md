# Troubleshooting Guide: Common Pitfalls & Solutions

**Last Updated:** February 16, 2026  
**Purpose:** Document common issues, gotchas, and their solutions

## Table of Contents

- [Troubleshooting Guide: Common Pitfalls \& Solutions](#troubleshooting-guide-common-pitfalls--solutions)
  - [Table of Contents](#table-of-contents)
  - [Docker \& Container Registry Issues](#docker--container-registry-issues)
    - [Docker Hub Rate Limits](#docker-hub-rate-limits)
  - [Vault Integration Issues](#vault-integration-issues)
    - [Missing vault {} Block](#missing-vault--block)
  - [Networking Problems](#networking-problems)
    - [CNI Bridge Plugin Not Available](#cni-bridge-plugin-not-available)
    - [Port Conflicts with Host Networking](#port-conflicts-with-host-networking)
  - [Database Connectivity](#database-connectivity)
    - [PostgreSQL Migration Issues](#postgresql-migration-issues)
    - [Database Choice for Monitoring Services](#database-choice-for-monitoring-services)
  - [Memory \& Resource Allocation](#memory--resource-allocation)
    - [Optimization Lessons Learned (February 2026)](#optimization-lessons-learned-february-2026)
  - [Service-Specific Issues](#service-specific-issues)
    - [Authelia SSO](#authelia-sso)
    - [FreshRSS](#freshrss)
    - [PostgreSQL](#postgresql)
    - [Authelia](#authelia)
    - [Nginx-Based Containers](#nginx-based-containers)
    - [Alpine/LinuxServer.io Containers (s6-overlay)](#alpinelinuxserverio-containers-s6-overlay)
    - [Homepage Dashboard](#homepage-dashboard)
    - [Uptime-Kuma](#uptime-kuma)
    - [Speedtest Tracker](#speedtest-tracker)
    - [Nomad Template Syntax \& Escaping](#nomad-template-syntax--escaping)
  - [General Best Practices](#general-best-practices)
    - [When Adding New Services](#when-adding-new-services)
    - [When Troubleshooting](#when-troubleshooting)
    - [Quick Diagnostic Commands](#quick-diagnostic-commands)
  - [When to Ask for Help](#when-to-ask-for-help)
  - [Future Improvements](#future-improvements)
    - [Needed Enhancements](#needed-enhancements)
    - [Documentation Additions](#documentation-additions)

---

## Docker & Container Registry Issues

### Docker Hub Rate Limits

**Symptom:**
```
Error response from daemon: toomanyrequests: You have reached your pull rate limit.
Failed to pull ghcr.io/... or docker.io/... image
429 Too Many Requests
```

**Root Cause:**  
Docker Hub limits unauthenticated pulls to **100 per 6 hours per IP address**. In a Nomad cluster with 6 nodes all pulling from the same IP, this limit is quickly reached.

**Anonymous vs Authenticated Limits:**
- **Anonymous (no login):** 100 pulls per 6 hours per IP
- **Authenticated (free account):** 200 pulls per 6 hours per user
- **Docker Pro/Team:** Higher limits (varies)

**Impact:**
System jobs like Traefik, Alloy, cAdvisor deployed to all 6 nodes consume 6 pulls each. Additional service deployments quickly exhaust the limit.

**Solution: Authenticate Docker on All Nodes**

1. **Get Docker Hub credentials:**
   - Free account: https://hub.docker.com/signup
   - Personal Access Token (recommended): Account Settings → Security → New Access Token

2. **Authenticate on your local machine:**
   ```bash
   docker login -u YOUR_USERNAME
   # Enter password or PAT when prompted
   ```

3. **Copy credentials to all Nomad clients:**
   ```fish
   # Fish shell script example
   for ip in 10.0.0.60 10.0.0.61 10.0.0.62 10.0.0.63 10.0.0.64 10.0.0.65
     echo "Configuring $ip..."
     # Copy from user's home directory to Docker daemon location
     ssh ubuntu@$ip "sudo mkdir -p /root/.docker"
     scp ~/.docker/config.json ubuntu@$ip:/tmp/
     ssh ubuntu@$ip "sudo mv /tmp/config.json /root/.docker/config.json"
     ssh ubuntu@$ip "sudo chmod 600 /root/.docker/config.json"
     
     # Restart Docker daemon to pick up new credentials
     ssh ubuntu@$ip "sudo systemctl restart docker"
   end
   ```

4. **Verify authentication:**
   ```bash
   ssh ubuntu@10.0.0.60 "sudo cat /root/.docker/config.json"
   # Should show auth token, not empty
   ```

**Why /root/.docker/ Instead of /home/ubuntu/.docker/?**

The Docker **daemon** runs as root and reads credentials from **root's home directory** (`/root/.docker/config.json`), not from the user who runs docker commands.

**Common Mistake:**
```bash
# ❌ Wrong - puts credentials in ubuntu user's home
scp config.json ubuntu@10.0.0.60:~/.docker/

# ✅ Correct - puts credentials where Docker daemon can find them
scp config.json ubuntu@10.0.0.60:/tmp/
ssh ubuntu@10.0.0.60 "sudo mv /tmp/config.json /root/.docker/"
```

**After Authentication:**
- Your cluster now has 200 pulls per 6 hours (instead of 100)
- Pulls are tracked per Docker Hub account, not per IP
- Rate limit resets every 6 hours from first pull

**Alternative: Use GitHub Container Registry (ghcr.io)**

Many images are mirrored on GHCR with more generous rate limits:
```hcl
config {
  # Instead of: image = "grafana/alloy:latest"
  image = "ghcr.io/grafana/alloy:latest"  # Often has higher limits
}
```

**Monitoring Rate Limits:**

Check remaining pulls via Docker Hub API:
```bash
TOKEN=$(curl -s "https://auth.docker.io/token?service=registry.docker.io&scope=repository:ratelimitpreview/test:pull" | jq -r .token)
curl -s -H "Authorization: Bearer $TOKEN" https://registry-1.docker.io/v2/ratelimitpreview/test/manifests/latest -I | grep -i ratelimit
```

Output:
```
ratelimit-limit: 200;w=21600
ratelimit-remaining: 195;w=21600
```

**Lesson Learned:**  
In multi-node clusters, **proactively authenticate all nodes with Docker Hub** before deploying services to avoid mid-deployment rate limiting failures.

---

## Vault Integration Issues

### Missing vault {} Block

**Symptom:**
```
Error: Missing: vault.read(secret/data/postgres/freshrss)
```

**Root Cause:**  
Services that use Vault templates in their configuration must have a `vault {}` block in the task definition to enable Vault integration. Without this block, the Nomad task won't have a Vault token to read secrets.

**Solution:**  
Add `vault {}` block to every task that uses Vault templates:

```hcl
task "myservice" {
  driver = "docker"
  
  # Required for Vault template access
  vault {}
  
  template {
    data = <<EOH
DB_PASSWORD={{ with secret "secret/data/postgres/myservice" }}{{ .Data.data.password }}{{ end }}
EOH
    destination = "secrets/db.env"
    env         = true
  }
}
```

**Important:**  
- Multi-task groups require `vault {}` in EVERY task that uses templates, including sidecar tasks
- Example: FreshRSS has both `freshrss` and `freshrss-cron` tasks - both need `vault {}`

---

## Networking Problems

### CNI Bridge Plugin Not Available

**Symptom:**
```
Constraint ${attr.plugins.cni.version.bridge} semver >= 0.4.0 filtered 3 nodes
```

**Root Cause:**  
This cluster doesn't have CNI plugins installed, so bridge networking is unavailable. Services attempting to use `network { mode = "bridge" }` will fail to place.

**Solution:**  
Use host networking instead:

```hcl
network {
  mode = "host"
  port "http" {
    static = 8082  # Choose an unused port
  }
}
```

**Workaround for Port Configuration:**  
When switching from bridge to host mode, you may need to configure the container to listen on a specific port:

```hcl
env {
  LISTEN = "0.0.0.0:${NOMAD_PORT_http}"  # For FreshRSS
  # Or other port configuration env vars for different services
}
```

### Port Conflicts with Host Networking

**Symptom:**
```
AH00072: make_sock: could not bind to address 0.0.0.0:80
Address already in use
```

**Root Cause:**  
When using `network { mode = "host" }`, containers share the host's network namespace. Multiple services can't bind to the same port (e.g., port 80).

**Solutions:**

1. **Use static ports and assign unique ports per service:**
```hcl
network {
  mode = "host"
  port "http" {
    static = 8082  # Unique port for this service
  }
}
```

2. **Configure the application to listen on the allocated port:**
```hcl
env {
  PORT = "${NOMAD_PORT_http}"
  # Or LISTEN, HTTP_PORT, etc. depending on the application
}
```

3. **Update Traefik routing to use the static port:**
```hcl
tags = [
  "traefik.enable=true",
  "traefik.http.routers.myservice.rule=Host(`myservice.home`)",
  "traefik.http.services.myservice.loadbalancer.server.port=8082",
]
```

**Port Allocation Reference:**
- Traefik: 80, 443, 8080
- PostgreSQL: 5432
- Prometheus: 9090
- FreshRSS: 8082
- Speedtest: 8081
- *(Add more as services are deployed)*

---

## Database Connectivity

### PostgreSQL Migration Issues

**Symptom:**  
Services fail to connect to PostgreSQL after migrating the database to a new node or changing connection methods.

**Common Errors:**
```
SQLSTATE[08006] [7] could not translate host name "postgresql.service.consul" to address
Connection refused on 10.0.0.61:5432 (when DB is actually on 10.0.0.60)
```

**Root Causes:**

1. **Outdated Consul Service Discovery:**  
   After moving PostgreSQL to a different node, Consul may cache old IP addresses or services may use stale connection strings.

2. **Hardcoded IP Addresses:**  
   Some services write database configuration to files during initialization, hardcoding the IP address at first boot.

**Solutions:**

1. **Use DNS Instead of Consul Discovery:**  
   Set up DNS (e.g., `postgresql.home` → `10.0.0.60`) and update all services:

   ```hcl
   env {
     DB_HOST = "postgresql.home"  # Instead of postgresql.service.consul
   }
   ```

2. **Restart All Dependent Services:**  
   After migrating PostgreSQL, redeploy all services using it:

   ```fish
   for service in grafana gitea freshrss
     nomad job run jobs/services/$service.nomad.hcl
   end
   ```

### Database Choice for Monitoring Services  
Nextcloud writes its database configuration to `config.php` during the **first boot only**. If PostgreSQL moves or the connection string changes, you must manually update the config file.

**Why This Happens:**  
Unlike other services that read environment variables on every start, Nextcloud's `config.php` is persistent and doesn't auto-update from env vars after initialization.

**Solution:**  
Always manually verify and update `config.php` after PostgreSQL changes:

```bash
# Check current DB host
grep dbhost /mnt/nas/nextcloud_config/config.php

# Update if incorrect
sudo sed -i "s/'dbhost' => '[^']*'/'dbhost' => 'postgresql.home'/" \
  /mnt/nas/nextcloud_config/config.php
```

### Database Choice for Monitoring Services

**Anti-Pattern: Don't Use Shared Databases for Monitoring**

**Problem:**  
Using shared PostgreSQL/MariaDB for monitoring services creates a circular dependency:
- Monitor tracks database health
- Database goes down
- Monitor can't access its own data to tell you the database is down

**Real Example - Uptime-Kuma:**  
Initially configured to use MariaDB. When MariaDB failed, Uptime-Kuma also failed, defeating the purpose of having a monitoring system.

**Solution:**  
Use self-contained storage (SQLite, embedded databases) for monitoring tools:

**Good For Shared Databases:**
- Application data (Gitea, Grafana)
- User authentication (Authelia)
- Content management (FreshRSS, Seafile)

**Keep Self-Contained:**
- Uptime-Kuma (monitoring)
- Alertmanager (alerting)
- Prometheus (metrics - uses TSDB)
- Loki (logs - uses file storage)

**Principle:** Monitoring infrastructure should be operationally independent from the systems it monitors.

---

## Memory & Resource Allocation

### Optimization Lessons Learned (February 2026)

**Background:**  
Initial resource allocations were overly generous, wasting ~3.5GB of RAM across the cluster.

**Findings:**

| Service | Initial | Actual Usage | Optimized To | Savings |
|---------|---------|-------------|--------------|---------|
| PostgreSQL | 2048 MB | ~64 MB (3%) | 512 MB | 1536 MB |
| Audiobookshelf | 2048 MB | ~144 MB (7%) | 512 MB | 1536 MB |
| Gitea | 1024 MB | ~205 MB (20%) | 512 MB | 512 MB |
| Grafana | 300 MB | 297 MB (99%) | 512 MB | -212 MB |

**Total Freed:** ~3.4 GB

**Lessons:**

1. **Monitor Before Optimizing:**  
   Use Prometheus metrics or `nomad alloc status` to check actual memory usage before reducing allocations.

2. **Leave Headroom:**  
   - Services at >80% usage: Increase allocation by 50-100%
   - Services at <30% usage: Safe to reduce to 2-3x actual usage
   - Services at 100%: Increase immediately (risk of OOM kills)

3. **Database Memory:**  
   PostgreSQL doesn't need gigabytes for small workloads (< 10 databases, low query volume). 512 MB is sufficient.

4. **Watch for OOM Kills:**  
   After optimization, monitor for 48-72 hours:
   ```bash
   nomad alloc status <alloc-id> | grep OOM
   ```

---

## Service-Specific Issues

### Authelia SSO

**Issue 1: Login Loop - Users Cannot Authenticate**

**Symptom:**  
Users are redirected to Authelia login page, enter credentials, but immediately get redirected back to login. Sessions don't persist, appearing as `<anonymous>` in Authelia logs.

**Root Cause:**  
Traefik's ForwardAuth middleware is using the wrong API endpoint. Authelia changed their API paths and the old `/api/authz/forward-auth` endpoint doesn't handle authentication properly.

**Solution:**  
Update Traefik's dynamic configuration to use the correct endpoint with redirect parameter:

```hcl
# In traefik.nomad.hcl - Dynamic configuration template
http:
  middlewares:
    authelia:
      forwardAuth:
        address: http://{{ range service "authelia" }}{{ .Address }}{{ end }}:9091/api/verify?rd=https://authelia.lab.hartr.net
        trustForwardHeader: true
        authResponseHeaders:
          - Remote-User
          - Remote-Groups
          - Remote-Email
          - Remote-Name
```

**Wrong:**  
```hcl
address: http://authelia:9091/api/authz/forward-auth  # Old endpoint, doesn't work
```

**Right:**  
```hcl
address: http://authelia:9091/api/verify?rd=https://authelia.lab.hartr.net  # Correct
```

**Issue 2: Double Authentication - Apps with Built-in Login**

**Symptom:**  
Services like Speedtest Tracker, Gitea, Nextcloud have their own authentication systems. When Authelia is placed in front of them, users must authenticate twice, or credentials don't match between systems.

**Root Cause:**  
Not all services should use SSO. Applications with robust built-in authentication (email/password, LDAP, OIDC) create a poor UX when fronted by another auth layer.

**Solution:**  
Remove Authelia middleware from services that have their own authentication:

```hcl
# DON'T protect these with Authelia:
service {
  tags = [
    "traefik.enable=true",
    "traefik.http.routers.speedtest.rule=Host(`speedtest.lab.hartr.net`)",
    # No authelia middleware - app has its own auth
  ]
}
```

**Services That Should NOT Use Authelia:**
- Speedtest Tracker (has Laravel Filament auth with email/password)
- Gitea (has user management, 2FA, OAuth)
- Vault (has token-based auth, policies)
- Authentik (it IS an auth system)

**Services That SHOULD Use Authelia:**
- Grafana (can use forward auth headers)
- Prometheus (no built-in auth)
- Alertmanager (basic or no auth)
- Traefik Dashboard (basic or no auth)
- Wiki.js (can use OAuth/OIDC)
- HomePage (read-only dashboard)
- Calibre (basic auth only)

**Issue 3: Resetting Passwords for Apps with Built-in Auth**

**Symptom:**  
Speedtest Tracker uses Laravel Filament admin panel with email-based login. If you forget the password, there's no password reset UI in development environments.

**Solution:**  
Use the Filament CLI tool inside the container to create/reset users:

```bash
# Get the allocation ID
export NOMAD_ADDR=http://10.0.0.50:4646
ALLOC_ID=$(nomad job status speedtest | grep running | awk '{print $1}' | head -1)

# Find artisan path (usually /app/www/artisan for LinuxServer.io containers)
nomad alloc exec -task speedtest $ALLOC_ID find /app -name artisan

# Create/reset admin user
nomad alloc exec -i -t -task speedtest $ALLOC_ID \
  php /app/www/artisan make:filament-user

# Follow interactive prompts for:
# - Name: jack@hartr.net
# - Email: jack@hartr.net  
# - Password: (enter new password)
```

**Other Common Artisan Paths:**
- LinuxServer.io containers: `/app/www/artisan`
- Standard Laravel: `/var/www/html/artisan`
- Custom builds: `/app/artisan`

**Issue 4: API Endpoints Blocked by Authelia - 401 Unauthorized on APIs**

**Symptom:**  
Services with API endpoints return 401 Unauthorized or redirect to Authelia login, even though the service has its own API authentication:

```
API Error: HTTP Error
URL: https://calibre.lab.hartr.net/opds/stats
Response: "401 Unauthorized - redirect to authelia.lab.hartr.net"
```

Or Grafana dashboards fail to load data from API endpoints.

**Root Cause:**  
Authelia's ForwardAuth middleware protects ALL paths for a domain by default. This breaks machine-to-machine API communication that uses different authentication (API keys, basic auth, OAuth tokens) than browser-based SSO.

**Examples of APIs That Should Bypass Authelia:**
- **Calibre OPDS API** (`/opds/*`) - Used by ebook reader apps with their own credentials
- **Grafana APIs** (`/api/*`, `/avatar/*`, `/public/*`) - Used by dashboards, data sources, and integrations
- **Gitea APIs** (`/api/*`) - Git operations and API tokens
- **Jenkins Build Triggers** (`/job/*/build`) - CI/CD webhooks

**Solution:**  
Add path-based bypass rules to Authelia's access control configuration in `authelia.nomad.hcl`:

```yaml
access_control:
  default_policy: deny
  
  rules:
    # Bypass API endpoints that have their own authentication
    
    # Calibre OPDS API - used by ebook readers
    - domain:
        - calibre.lab.hartr.net
      resources:
        - "^/opds.*$"
      policy: bypass
    
    # Grafana API - used for dashboards, data sources, and integrations
    - domain:
        - grafana.lab.hartr.net
      resources:
        - "^/api/.*$"
        - "^/avatar/.*$"
        - "^/public/.*$"
      policy: bypass
    
    # Protected services - require authentication for web UI
    - domain:
        - calibre.lab.hartr.net
        - grafana.lab.hartr.net
      policy: one_factor
```

**Key Points:**
- Rules are evaluated **in order** - bypass rules must come BEFORE catch-all protection rules
- Use regex patterns in `resources` field to match URL paths
- The web UI (`/`) is still protected by Authelia, only specific API paths bypass it
- After updating, redeploy Authelia: `nomad job run jobs/services/authelia.nomad.hcl`

**Verification:**
```bash
# API endpoint should return 200 (bypassed)
curl -I https://calibre.lab.hartr.net/opds/stats
# HTTP/2 200

# Web UI should return 302 redirect (protected)
curl -I https://calibre.lab.hartr.net/
# HTTP/2 302
# location: https://authelia.lab.hartr.net/?rd=...
```

**When to Use API Bypass:**
- ✅ Machine-to-machine APIs (OPDS, webhook endpoints, REST APIs)
- ✅ Public assets that don't need protection (`/public/*`, `/static/*`)
- ✅ Health check endpoints used by monitoring (`/health`, `/healthz`)
- ❌ Admin APIs that should require authentication
- ❌ User data endpoints that contain sensitive information

**Issue 5: Session Cookie Domain Must Have Leading Dot**

**Symptom:**  
Authelia sessions don't persist across subdomains. Works on `authelia.lab.hartr.net` but not `grafana.lab.hartr.net`.

**Root Cause:**  
Cookie domain must include leading dot to work across all subdomains.

**Solution:**
```yaml
# In authelia configuration.yml
session:
  cookies:
    - domain: .lab.hartr.net  # Note the leading dot!
      authelia_url: https://authelia.lab.hartr.net
```

**Wrong:** `domain: lab.hartr.net` (no leading dot)  
**Right:** `domain: .lab.hartr.net` (with leading dot)

### FreshRSS

**Issue 1: Missing Vault Integration**  
See [Vault Integration Issues](#vault-integration-issues) above. Both `freshrss` and `freshrss-cron` tasks need `vault {}`.

**Issue 2: Port Configuration**  
FreshRSS uses an Apache container that defaults to port 80. When using host networking with a static port, you must configure it:

```hcl
env {
  LISTEN = "0.0.0.0:${NOMAD_PORT_http}"
}
```

**Issue 3: Cron Task Needs Same Vault Access**  
The `freshrss-cron` sidecar task also reads database credentials, so it needs:
- Its own `vault {}` block
- Its own template for database credentials
- Access to the same Vault secrets as the main task

### PostgreSQL

**Issue: Database Initialization**  
PostgreSQL requires databases and users to be created before applications can use them. 

**Solution:**  
Use the automated `init-databases` task in `postgresql.nomad.hcl`:

1. Add new database to the SQL script in the template block
2. Redeploy PostgreSQL: `nomad job run jobs/services/postgresql.nomad.hcl`
3. The init script is idempotent - safe to run multiple times

See [POSTGRESQL.md](POSTGRESQL.md) for details.

### Authelia

**Issue: PostgreSQL Configuration Parse Error**

**Symptom:**
```
Configuration parsed and loaded with errors: storage.postgres.address could not decode 'tcp://[localhost:5432]:5432'
Authelia container fails health checks and won't start
```

**Root Cause:**  
Authelia deprecated the separate `host` and `port` configuration fields for PostgreSQL in favor of a single `address` field in the `tcp://host:port` format. Using the old fields causes Authelia to auto-construct a malformed address.

**Old (Deprecated) Configuration - Causes Errors:**
```yaml
storage:
  postgres:
    host: {{ range service "postgresql" }}{{ .Address }}{{ end }}
    port: 5432
    database: authelia
    username: authelia
    password: {{ with secret "secret/data/postgres/authelia" }}{{ .Data.data.password }}{{ end }}
```

**Error Result:**
```
# Authelia incorrectly combines these into:
tcp://[10.0.0.60:5432]:5432  # ❌ Malformed - double ports!
```

**New (Correct) Configuration - Works:**
```yaml
storage:
  postgres:
    address: tcp://{{ range service "postgresql" }}{{ .Address }}{{ end }}:5432
    database: authelia
    username: authelia
    password: {{ with secret "secret/data/postgres/authelia" }}{{ .Data.data.password }}{{ end }}
```

**Correct Result:**
```
tcp://10.0.0.60:5432  # ✅ Properly formatted
```

**How to Fix:**

1. **Update authelia.nomad.hcl configuration:**
   ```hcl
   template {
     data = <<EOH
   # ... other config ...
   storage:
     encryption_key: {{ with secret "secret/data/authelia/config" }}{{ .Data.data.encryption_key }}{{ end }}
     postgres:
       address: tcp://{{ range service "postgresql" }}{{ .Address }}{{ end }}:5432  # ✅ New format
       database: authelia
       username: authelia
       password: {{ with secret "secret/data/postgres/authelia" }}{{ .Data.data.password }}{{ end }}
   EOH
   }
   ```

2. **Redeploy Authelia:**
   ```bash
   nomad job run jobs/services/authelia.nomad.hcl
   ```

3. **Verify successful startup:**
   ```bash
   nomad job status authelia
   # Should show: Status = successful, Healthy = 1
   ```

**Reference:**
- Authelia docs: https://www.authelia.com/configuration/storage/postgres/
- Deprecation notice appeared in Authelia v4.38+

**Lesson Learned:**  
When container logs show configuration parse errors with malformed addresses, check if you're using deprecated configuration syntax. The old `host` + `port` pattern is common in older documentation but may have been replaced with unified `address` fields.

### Nginx-Based Containers

**Issue: Permission Errors on Startup**

**Symptom:**
```
[emerg] 1#1: chown("/var/cache/nginx/client_temp", 101) failed (1: Operation not permitted)
nginx: [emerg] chown("/var/cache/nginx/client_temp", 101) failed (1: Operation not permitted)
Docker container exited with non-zero exit code: 1
```

**Root Cause:**  
Many nginx-based containers (like it-tools, some custom apps) need to initialize cache directories and change ownership. Without proper permissions, nginx fails to start.

**Incorrect Solution (Won't Work):**  
```hcl
config {
  image = "corentinth/it-tools:latest"
  cap_add = ["CHOWN", "SETUID", "SETGID"]  # ❌ Nomad Docker driver rejects this
}
```

**Error:**
```
driver does not allow the following capabilities: chown, setgid, setuid
```

**Correct Solution:**  
Use privileged mode instead:

```hcl
config {
  image = "corentinth/it-tools:latest"
  ports = ["http"]
  privileged = true  # ✅ Grants necessary permissions
}
```

**When to Use Privileged Mode:**
- Nginx-based containers that manage internal directories
- Services requiring specific system capabilities
- Applications needing host-level access (like Traefik for port binding)

**Security Note:**  
While `privileged = true` grants broad permissions, in a homelab context where all services are trusted, this is acceptable. For production environments, consider building custom images with proper user permissions.

---

**Issue: Nginx Redirect Loops (Laravel/PHP Applications)**

**Symptom:**
```
nginx error log:
2026/02/16 21:55:46 [error] 302#302: *11 rewrite or internal redirection cycle 
while internally redirecting to "/index.php", client: 10.0.0.60, 
server: _, request: "GET /login HTTP/1.1"

HTTP 500 Internal Server Error from nginx
Service fails health checks with 500 responses
```

**Root Cause:**  
Incorrect `try_files` directive in nginx configuration for Laravel/PHP applications. Using `try_files $uri $uri/ /index.php?$query_string;` causes infinite redirect loops because:
1. nginx tries the URI as a file
2. nginx tries the URI as a directory  
3. nginx internally redirects to `/index.php?$query_string`
4. Step 3 matches the `location ~ \.php$` block
5. PHP processes the request
6. **BUT** - The query string handling is incorrect, causing the loop

**Affected Applications:**
- BookStack (LinuxServer.io image)
- Any Laravel-based application
- PHP frameworks using front-controller pattern

**Solution:**  
Use proper Laravel nginx configuration:

```nginx
location / {
    try_files $uri $uri/ /index.php$is_args$args;  # ✅ Correct
    # NOT: try_files $uri $uri/ /index.php?$query_string;  ❌ Causes loop
}
```

Or even simpler:
```nginx
location / {
    try_files $uri $uri/ /index.php;
}
```

**Explanation:**
- `$is_args` - Evaluates to `?` if query string exists, empty otherwise
- `$args` - The actual query string (equivalent to `$query_string`)
- `$is_args$args` - Properly formats: `/index.php?foo=bar` or `/index.php` (no trailing `?`)
- Manual `?$query_string` - Always adds `?`, even when empty: `/index.php?`

**Detection:**
```bash
# Check nginx error logs for redirect cycles
ssh ubuntu@<node_ip> "sudo tail -50 /mnt/nas/<service>_config/log/nginx/error.log" | grep "redirection cycle"

# Test endpoint directly
curl -I http://<node_ip>:<port>/login
# Should return 200 or 302, NOT 500
```

**Prevention:**
- Use tested nginx configurations from official framework docs
- Test custom nginx configs in development first
- Always check error logs after deployment
- Add health checks that verify successful responses (not just TCP)

### Alpine/LinuxServer.io Containers (s6-overlay)

**Issue: s6-overlay Permission Errors**

**Symptom:**
```
s6-applyuidgid: fatal: unable to set supplementary group list: Operation not permitted
Docker container exited with non-zero exit code: 256
```

or

```
setgroups: Operation not permitted
Container fails to start or fails health checks repeatedly
```

**Root Cause:**  
Many popular LinuxServer.io containers (and other Alpine-based images) use [s6-overlay](https://github.com/just-containers/s6-overlay) as their init system. The s6-overlay system needs to:
- Change process user/group IDs (su-exec)
- Set supplementary group lists (setgroups)
- Manage process permissions for running services as non-root users

Without privileged mode, these operations fail with "Operation not permitted" errors.

**Affected Containers:**
- LinuxServer.io images: `linuxserver/calibre-web`, `linuxserver/speedtest-tracker`, `linuxserver/audiobookshelf`
- Alpine-based PostgreSQL: `postgres:16-alpine`
- Redis Alpine: `redis:alpine`
- Authelia: `authelia/authelia`
- Grafana Alloy: `grafana/alloy`
- Traefik: `traefik:v3.0`

**Common Error Patterns:**

1. **s6-overlay specific:**
   ```
   s6-applyuidgid: fatal: unable to set supplementary group list: Operation not permitted
   ```

2. **su-exec errors:**
   ```
   su-exec: setgroups(1, [1000]): Operation not permitted
   ```

3. **Generic permission denied:**
   ```
   chown: changing ownership of '/config': Operation not permitted
   ```

**Solution:**  
Add `privileged = true` to the Docker config:

```hcl
task "myservice" {
  driver = "docker"
  
  config {
    image = "linuxserver/calibre-web:latest"
    ports = ["http"]
    privileged = true  # ✅ Required for s6-overlay
  }
}
```

**Why This Happens:**

Docker containers run with a restricted set of Linux capabilities by default. The s6-overlay init system requires:
- `CAP_SETUID` - Change user IDs
- `CAP_SETGID` - Change group IDs  
- `CAP_SETFCAP` - Set file capabilities

While you might think to use `cap_add`, the Nomad Docker driver doesn't allow adding capabilities directly:

```hcl
# ❌ This won't work - Nomad rejects it
config {
  cap_add = ["SETUID", "SETGID", "SETFCAP"]
}
# Error: driver does not allow the following capabilities: setgid, setuid, setfcap
```

**Workaround - Use Privileged Mode:**

The `privileged = true` flag grants all necessary capabilities:

```hcl
# ✅ This works
config {
  privileged = true
}
```

**Services Successfully Deployed with This Fix (Feb 2026):**
- ✅ Traefik (reverse proxy, port 80/443 binding)
- ✅ PostgreSQL (postgres:16-alpine, setgroups for postgres user)
- ✅ Redis (redis:alpine, setgroups for redis user)
- ✅ Authelia (SSO authentication, setgroups)
- ✅ Grafana Alloy (metrics/logs collection)
- ✅ Calibre-Web (ebook library management)
- ✅ Speedtest Tracker (network testing)
- ✅ Audiobookshelf (audiobook management)

**When to Use Privileged Mode:**
1. **LinuxServer.io containers** - Almost always need it due to s6-overlay
2. **Alpine-based official images** - Often need it for su-exec/setgroups
3. **Services binding to privileged ports** - Like Traefik on ports 80/443
4. **Services managing file ownership** - Containers that chown data directories

**Security Considerations:**

In a **homelab environment**, using `privileged = true` is acceptable because:
- All services are under your control
- No untrusted code is running
- Convenience and functionality outweigh security concerns
- Isolation is still provided at the VM/cluster level

In **production environments**, alternatives include:
- Building custom container images with correct user/group setup
- Using rootless containers (requires different runtime configuration)
- Pre-creating directories with correct ownership on the host
- Using container images designed to run as non-root without init systems

**Debugging Container Permission Issues:**

1. **Check container logs for permission errors:**
   ```bash
   nomad alloc logs <alloc-id> 2>&1 | grep -i "operation not permitted"
   ```

2. **Look for s6-overlay or su-exec errors:**
   ```bash
   nomad alloc logs <alloc-id> 2>&1 | grep -E "(s6-|su-exec|setgroups)"
   ```

3. **Verify container is LinuxServer.io or Alpine-based:**
   ```bash
   # Check the image in the job file
   grep "image =" jobs/services/myservice.nomad.hcl
   ```

4. **Add privileged mode and redeploy:**
   ```hcl
   config {
     image = "linuxserver/myservice:latest"
     privileged = true  # Add this line
   }
   ```

5. **Verify deployment succeeded:**
   ```bash
   nomad job status myservice
   # Look for "Status = successful" and "Healthy = 1"
   ```

**Lesson Learned:**  
When deploying LinuxServer.io or Alpine-based containers, **preemptively add `privileged = true`** to save debugging time. The s6-overlay permission requirement is consistent across these images.

---

**Issue: s6-overlay Process Escape with Host Networking**

**Symptom:**
```
Port conflicts persist across container removals
PHP-FPM unable to bind listening socket for address '127.0.0.1:9000': Address in use (98)
Orphaned processes visible on host OS: ps -ef shows s6-svscan, nginx, php-fpm
Killing individual processes doesn't help - they respawn automatically
```

**Root Cause:**  
**CRITICAL BUG**: When using `network_mode = "host"` with LinuxServer.io containers (s6-overlay), the s6-overlay init system can **escape to the host OS** and persist after container removal. The s6-svscan supervisor runs directly on the bare metal host, spawning and supervising nginx, PHP-FPM, and other services outside of Docker's control.

**Discovery Timeline (BookStack Deployment - Feb 2026):**
1. Service returns 500 errors (nginx redirect loop)
2. Fixed redirect loop, still getting 500 errors
3. Direct port test shows "Address in use" for port 9000 (PHP-FPM)
4. `docker stop` and `nomad job stop` don't clear the port
5. Found orphaned PHP-FPM processes on host: `ps -ef | grep php-fpm`
6. Killed PHP-FPM processes, but they **respawned** within seconds
7. Traced parent PIDs: discovered s6-svscan (PID 1078383) running on host
8. Process tree showed s6-supervise children respawning killed processes:
   ```
   root 1078383     1     0 20:41 ?        s6-svscan /etc/s6/
     ├─ root 1078558  1078383  nginx: master process
     ├─ root 1082290  1078383  php-fpm: master process (port 9000)
     ├─ root 1083824  1078383  s6-supervise nginx
     └─ root 1083825  1078383  s6-supervise php-fpm
   ```

**Why This Happens:**
- Host networking (`network_mode = "host"`) removes network namespace isolation
- s6-overlay PID 1 init system can attach to host PID namespace
- When container "stops", Docker loses track of processes
- s6-svscan continues running on host, supervising escaped services
- Processes block ports for ALL future containers on that node

**Detection:**
```bash
# Check for escaped s6-svscan processes
ssh ubuntu@<node_ip> 'ps -ef | grep "[s]6-svscan /etc/s6"'

# Check for orphaned PHP-FPM/nginx
ssh ubuntu@<node_ip> 'sudo ss -tlnp | grep ":9000"'

# Trace process tree to find supervisor root
ps -ef | grep <pid>  # Find parent PID
```

**Solution:**
1. **Stop the Nomad job:**
   ```bash
   nomad job stop <job-name>
   ```

2. **Clean persistent volumes:**
   ```bash
   ssh ubuntu@<node_ip> "sudo rm -rf /mnt/nas/<service>_config/*"
   ```

3. **Kill s6-svscan root process (not individual services!):**
   ```bash
   ssh ubuntu@<node_ip> 'ps -ef | grep "[s]6-svscan /etc/s6"'
   # Find the PID (e.g., 1078383)
   ssh ubuntu@<node_ip> 'sudo kill -9 1078383'
   ```

4. **Verify ports are clear:**
   ```bash
   ssh ubuntu@<node_ip> 'sudo ss -tlnp | grep ":<port>" || echo "Port clear"'
   ```

5. **Redeploy with clean state:**
   ```bash
   nomad job run jobs/services/<service>.nomad.hcl
   ```

**Prevention Strategies:**

1. **Use distinct_hosts constraint** to spread allocations:
   ```hcl
   constraint {
     distinct_hosts = true  # Prevents multiple instances on same node
   }
   ```

2. **Consider bridge networking** (if CNI available):
   ```hcl
   network {
     mode = "bridge"  # Better isolation, but requires CNI plugins
   }
   ```

3. **Monitor for orphaned processes** after deployments:
   ```bash
   # Add to monitoring or post-deployment checks
   for node in 10.0.0.60 10.0.0.61 10.0.0.62 10.0.0.63 10.0.0.64 10.0.0.65; do
     ssh ubuntu@$node 'ps -ef | grep "[s]6-svscan /etc/s6" | wc -l'
   done
   ```

4. **Document affected services:**
   - BookStack (LinuxServer.io image)
   - Any service using s6-overlay + host networking
   - PHP-FPM based applications (port 9000 common)
   - nginx-based containers (ports 80/443)

**Impact:**
- **Severity**: CRITICAL - Blocks future deployments on affected node
- **Scope**: Any LinuxServer.io container with host networking
- **Recovery Time**: 5-10 minutes (stop job, identify processes, kill root supervisor)
- **Data Loss Risk**: LOW (if persistent volumes used correctly)

**Related Issues:**
- Port conflicts appearing "randomly" after redeployments
- Services fail to start with "Address already in use"
- Docker shows no containers, but ports still occupied
- Nomad shows allocation as "complete" but processes remain

**Future Investigation:**
- Test if `pidmode = "host"` explicitly triggers this
- Evaluate if PID namespace isolation prevents escape
- Consider automated cleanup scripts for node maintenance

### Homepage Dashboard

**Issue 1: Configuration Changes Not Appearing**

**Symptom:**  
You update `services.yaml` in the homepage job template and redeploy, but changes don't appear in the UI.

**Root Cause:**  
Homepage caches configuration and may not reload it immediately, especially if the deployment fails health checks and rolls back.

**Solution:**
1. Verify the job deployed successfully (not rolled back)
2. Check job version increased: `nomad job status homepage`
3. Force a restart: `nomad job restart homepage`
4. Clear browser cache or hard refresh (Cmd+Shift+R / Ctrl+Shift+F5)

**Issue 2: Deployment Fails Health Checks**

**Symptom:**
```
Deployment "xxx" failed - rolling back to job version X
Task Group  Desired  Placed  Healthy  Unhealthy
homepage    1        1       0        1
```

**Root Cause:**  
Homepage (Next.js application) takes significant time to start - typically 30-60 seconds, but can take longer with many services configured. Default health check timing (30s) is too aggressive.

**Default Configuration (Too Aggressive):**
```hcl
update {
  max_parallel      = 1
  health_check      = "checks"
  min_healthy_time  = "5s"
  healthy_deadline  = "30s"   # ❌ Too short
  progress_deadline = "1m"    # ❌ Too short
  auto_revert       = true
}
```

**Corrected Configuration:**
```hcl
update {
  max_parallel      = 1
  health_check      = "checks"
  min_healthy_time  = "10s"
  healthy_deadline  = "2m"    # ✅ Allows time for Next.js startup
  progress_deadline = "3m"    # ✅ Prevents premature rollback
  auto_revert       = true
}
```

**Explanation:**
- `healthy_deadline`: How long to wait for the service to become healthy
- `progress_deadline`: How long the deployment can run before being considered failed
- Homepage needs 1-2 minutes to fully initialize, especially after configuration changes

**When to Use Longer Timeouts:**
- Next.js applications (Homepage, custom dashboards)
- Services with large initialization (database migrations, cache warming)
- Heavy container images with slow startup times
- Services that download/generate content on first boot

**Debug Steps:**
1. Check allocation logs: `nomad alloc logs <alloc-id>`
2. Look for successful startup message: `✓ Ready in 1007ms`
3. Verify container is running: `nomad alloc status <alloc-id>`
4. If container starts but fails health checks, increase timeouts
5. If container won't start at all, check stderr logs for errors

### Uptime-Kuma

**Issue 1: Monitoring Anti-Pattern - Don't Use Shared Database**

**Problem:**  
Initially configured Uptime-Kuma to use shared MariaDB for its monitoring data. When MariaDB went down, the monitoring system (which should tell us about outages) also went down.

**Why This is Bad:**  
- **Circular dependency:** Monitor monitors database → database fails → monitor fails → can't see that database failed
- **Cascading failures:** Single database outage takes down all monitoring infrastructure
- **Defeats the purpose:** Monitoring should be independent of the systems it monitors

**Solution:**  
Revert to SQLite for self-contained monitoring:

```hcl
task "uptime-kuma" {
  driver = "docker"
  
  # No vault {} block needed - no external database
  
  env {
    UPTIME_KUMA_DISABLE_FRAME_SAMEORIGIN = "true"
    DATA_DIR = "/app/data"
    # Uses default SQLite at /app/data/kuma.db
  }
  
  # No database connection template needed
}
```

**Lesson:** Monitoring tools should have minimal external dependencies so they remain operational when the systems they monitor fail.

**Issue 2: Persistent Configuration Files Cause Connection Errors**

**Symptom:**  
After changing job definition from MariaDB to SQLite, service fails with:
```
[SERVER] ERROR: Failed to prepare your database: connect ECONNREFUSED 10.0.0.60:3306
```

**Root Cause:**  
Uptime-Kuma stores database configuration in `db-config.json` in the data directory. This file persists across job redeployments and overrides the job definition.

**Directory Contents Example:**
```bash
/mnt/nas/uptime-kuma/
├── db-config.json          # ❌ Contains old MariaDB settings
├── error.log               # Shows connection refused errors
├── docker-tls/
├── screenshots/
└── upload/
```

**db-config.json Example:**
```json
{
    "type": "mariadb",
    "port": 3306,
    "hostname": "mariadb.lab.hartr.net",
    "username": "uptimekuma",
    "password": "uptimekuma_secure_2026",
    "dbName": "uptimekuma"
}
```

**Solution:**  
Clear the data directory to force SQLite initialization:

```bash
# Stop the job
nomad job stop uptime-kuma

# Clear ALL files (will lose existing monitors and data)
ssh ubuntu@10.0.0.60 "sudo rm -rf /mnt/nas/uptime-kuma/*"

# Redeploy with SQLite configuration
nomad job run jobs/services/observability/uptime-kuma/uptime-kuma.nomad.hcl
```

**Important:** This destroys all existing monitors, status pages, and historical data. You'll need to:
1. Create new admin account on first login
2. Re-add all monitoring checks
3. Reconfigure status page (use slug "default" for Homepage widget)

**Issue 3: Volume Name vs Directory Path Mismatch**

**Gotcha:**  
The Nomad volume is named `uptime_kuma_data` (underscore) but points to `/mnt/nas/uptime-kuma/` (dash).

**Ansible Configuration:**
```hcl
# ansible/roles/nomad-client/templates/nomad-client.hcl.j2
host_volume "uptime_kuma_data" {
  path = "{{ nas_mount_point }}/uptime-kuma"  # ← dash, not underscore
}
```

**When troubleshooting, check BOTH locations:**
```bash
# These are different directories!
ls /mnt/nas/uptime_kuma_data/   # ❌ Doesn't exist
ls /mnt/nas/uptime-kuma/        # ✅ Actual data location
```

**Prevention:**  
Keep volume names and directory paths consistent to avoid confusion.

### Speedtest Tracker

**Issue 1: 404 Error on First Access**

**Symptom:**  
After deploying Speedtest Tracker, accessing `https://speedtest.lab.hartr.net` returns a 404 error.

**Root Causes:**
1. PostgreSQL database/user not created despite Vault secret existing
2. No admin user created for Filament (Laravel admin panel)

**Diagnosis:**

1. **Check container logs for database authentication errors:**
   ```fish
   nomad alloc logs <speedtest-alloc-id> 2>&1 | grep -i "password authentication failed"
   ```
   
   Expected error:
   ```
   SQLSTATE[08006] [7] connection to server at "10.0.0.60", port 5432 failed:
   FATAL: password authentication failed for user "speedtest"
   ```

2. **Verify database and user exist in PostgreSQL:**
   ```fish
   # Check if database exists
   nomad alloc exec -task postgres <postgres-alloc-id> psql -U postgres -c "\l" | grep speedtest
   
   # Check if user exists
   nomad alloc exec -task postgres <postgres-alloc-id> psql -U postgres -c "\du" | grep speedtest
   ```

3. **Verify Vault secret exists:**
   ```fish
   vault kv get secret/postgres/speedtest
   ```

**Solution - Manual Database Creation:**

If the init-databases task failed or didn't run, manually create the database and user:

```fish
# Get the password from Vault
export PASSWORD=$(vault kv get -field=password secret/postgres/speedtest)

# Get PostgreSQL allocation ID
export POSTGRES_ALLOC=$(nomad job status postgresql | grep running | awk '{print $1}' | head -1)

# Create database
nomad alloc exec -task postgres $POSTGRES_ALLOC psql -U postgres -c "CREATE DATABASE speedtest;"

# Create user with Vault password
nomad alloc exec -task postgres $POSTGRES_ALLOC psql -U postgres -c "CREATE USER speedtest WITH ENCRYPTED PASSWORD '$PASSWORD';"

# Grant privileges
nomad alloc exec -task postgres $POSTGRES_ALLOC psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE speedtest TO speedtest;"

# Grant schema permissions
nomad alloc exec -task postgres $POSTGRES_ALLOC psql -U postgres -d speedtest -c "GRANT ALL ON SCHEMA public TO speedtest;"
```

**Solution - Create Admin User:**

Speedtest Tracker uses Filament (Laravel admin panel) which requires creating a user via artisan command:

```fish
# Get Speedtest allocation ID
export SPEEDTEST_ALLOC=$(nomad job status speedtest | grep running | awk '{print $1}' | head -1)

# Create admin user (non-interactive)
nomad alloc exec -i=false -t=false $SPEEDTEST_ALLOC \
  php /app/www/artisan make:filament-user \
  --name=admin \
  --email=admin@lab.hartr.net \
  --password=changeme123
```

**Expected Output:**
```
INFO  Success! admin@lab.hartr.net may now log in at https://speedtest.lab.hartr.net/admin/login.
```

**After Fix:**
1. Restart the Speedtest job: `nomad job run jobs/services/infrastructure/speedtest/speedtest.nomad.hcl`
2. Access the admin panel: `https://speedtest.lab.hartr.net/admin/login`
3. Log in with credentials created above
4. **Change password immediately** after first login

**Prevention:**

1. **Always verify init-databases task ran successfully:**
   ```fish
   nomad alloc logs <postgres-alloc-id> init-databases | grep "Database initialization completed"
   ```

2. **Add database creation check to deployment workflow:**
   ```fish
   # After deploying PostgreSQL, verify all databases exist
   nomad alloc exec -task postgres <postgres-alloc-id> psql -U postgres -c "\l" | grep -E "(speedtest|uptimekuma|vaultwarden)"
   ```

3. **Document required artisan commands** in service-specific docs for Laravel/PHP applications

**Fish Shell Gotcha:**  
When troubleshooting, remember that Fish shell **does not support heredocs** (`<<EOF` syntax). Use one of these alternatives:
- Multiple single commands with `-c` flag (as shown above)
- Echo piped to command: `echo "SQL COMMAND" | nomad alloc exec ...`
- Temp files: `echo "SQL" > /tmp/sql.txt && cat /tmp/sql.txt | nomad alloc exec ...`

---

### Nomad Template Syntax & Escaping

**Issue: Nginx Variables Not Rendering Correctly in Templates**

**Symptom:**
```
nginx error log:
2026/02/16 22:06:01 [emerg] 1046#1046: invalid variable name in 
/config/nginx/site-confs/default.conf:13

Generated nginx config shows literal escape sequences:
try_files \$uri \$uri/ /index.php\$is_args\$args;  # ❌ Wrong
try_files $$uri $$uri/ /index.php$$is_args$$args;  # ❌ Also wrong

Service fails to start, ports not bound
```

**Root Cause:**  
Nomad's template syntax interprets `$` and `$$` specially:
- `$variable` - Nomad tries to interpolate as Nomad variable (fails if doesn't exist)
- `$$variable` - Nomad renders as literal `$$variable` (not `$variable`)
- `\$variable` - Escapes to `\$variable` in output (not `$variable`)

Nginx needs actual `$` for its own variables (`$uri`, `$args`, `$document_root`, etc.).

**Solution:**  
Use Nomad's template language to output literal `$`:

```hcl
template {
  destination = "local/nginx-default.conf"
  data        = <<EOH
server {
    location / {
        # ✅ Correct: Use {{`$`}} for each nginx variable
        try_files {{`$`}}uri {{`$`}}uri/ /index.php{{`$`}}is_args{{`$`}}args;
    }
    
    location ~ \.php{{`$`}} {
        fastcgi_param SCRIPT_FILENAME {{`$`}}document_root{{`$`}}fastcgi_script_name;
        fastcgi_param PATH_INFO {{`$`}}fastcgi_path_info;
        fastcgi_param QUERY_STRING {{`$`}}query_string;
    }
}
EOH
}
```

**How It Works:**
- `{{`$`}}` - Nomad template that renders a literal backtick-quoted dollar sign
- At render time: `{{`$`}}uri` → `$uri` in the output file  
- Nginx then interprets `$uri` as an nginx variable

**Alternative Approaches (That Don't Work):**

```hcl
# ❌ Attempt 1: Double dollar signs
try_files $$uri $$uri/ /index.php$$is_args$$args;
# Result: try_files $$uri $$uri/ /index.php$$is_args$$args; (literal $$)

# ❌ Attempt 2: Backslash escaping  
try_files \$uri \$uri/ /index.php\$is_args\$args;
# Result: try_files \$uri \$uri/ /index.php\$is says\$args; (literal \$)

# ❌ Attempt 3: Mixing approaches
try_files $uri $uri/ /index.php$is_args$args;
# Result: Error - Nomad tries to interpolate $uri as Nomad variable
```

**Testing Template Rendering:**

```bash
# Check what Nomad actually generated
nomad alloc exec -task=<task> <alloc-id> cat /local/<template-file>

# Or from host (if using bind mount to /config)
ssh ubuntu@<node_ip> "sudo cat /mnt/nas/<service>_config/<file>"

# Verify dollar signs are single, not doubled or escaped
grep "try_files" <file>
# Should show: try_files $uri $uri/ ...
```

**Common Variables Needing Escaping:**

In nginx configs:
- `$uri` → `{{`$`}}uri`
- `$args` / `$query_string` → `{{`$`}}args` / `{{`$`}}query_string`  
- `$is_args` → `{{`$`}}is_args`
- `$document_root` → `{{`$`}}document_root`
- `$fastcgi_script_name` → `{{`$`}}fastcgi_script_name`
- `$host` → `{{`$`}}host`
- `$request_uri` → `{{`$`}}request_uri`

In shell scripts (if templating bash/fish):
- Bash: `${var}` → `{{`$`}}{var}` or use `$$` for literal
- Fish: Generally avoid templating fish scripts; use env vars instead

**Real-World Example (BookStack):**

```hcl
template {
  destination = "local/nginx-default.conf"
  data        = <<EOH
server {
    listen 8083 default_server;
    root /app/www/public;
    index index.php index.html;
    
    location / {
        try_files {{`$`}}uri {{`$`}}uri/ /index.php{{`$`}}is_args{{`$`}}args;
    }
    
    location ~ \.php{{`$`}} {
        fastcgi_split_path_info ^(.+\.php)(/.+){{`$`}};
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_param SCRIPT_FILENAME {{`$`}}document_root{{`$`}}fastcgi_script_name;
        fastcgi_param PATH_INFO {{`$`}}fastcgi_path_info;
    }
}
EOH
}
```

**Rendered Output:**
```nginx
server {
    listen 8083 default_server;
    root /app/www/public;
    index index.php index.html;
    
    location / {
        try_files $uri $uri/ /index.php$is_args$args;  # ✅ Correct!
    }
    
    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param PATH_INFO $fastcgi_path_info;
    }
}
```

**Documentation References:**
- [Nomad Template Syntax](https://developer.hashicorp.com/nomad/docs/job-specification/template#template-syntax)
- [Go Template Documentation](https://pkg.go.dev/text/template)
- Nomad uses Go's `text/template` package with additional functions

**Lesson Learned:**  
When templating config files that use `$` for their own variables (nginx, bash, etc.), **always use `{{`$`}}` for literal dollar signs**. Test template rendering early in development to catch escaping issues before deployment.

---

## General Best Practices

### When Adding New Services

1. **Check for existing documentation** in `/docs` before implementing
2. **Start with host networking** unless bridge is specifically needed
3. **Allocate 2-3x expected memory** initially, optimize later
4. **Add vault {} blocks** if using Vault templates (even in sidecar tasks)
5. **Use static ports** when using host networking to avoid conflicts
6. **Document port allocations** to prevent future conflicts
7. **Test database connectivity** after PostgreSQL changes
8. **Add to Traefik** with appropriate routing rules
9. **Set appropriate health check timeouts** - use 2-3 minute deadlines for heavy services (Next.js, databases, etc.)
10. **Use privileged mode for nginx containers** if you encounter chown/permission errors
11. **Keep monitoring services self-contained** - use SQLite/embedded storage for monitoring tools (Uptime-Kuma, Alertmanager) to avoid circular dependencies with monitored databases

### When Troubleshooting

1. **Check Nomad allocation status:** `nomad alloc status <id>`
2. **Read stderr logs:** `nomad alloc logs -stderr <id>`
3. **Verify Vault access:** Ensure `vault {}` block exists in task
4. **Check port conflicts:** `nomad alloc status` shows port bindings
5. **SSH to client:** Inspect volume mounts, config files, network state
6. **Restart service:** `nomad job run <jobfile>` is often sufficient
7. **Check Consul:** `consul catalog services` for service registration

### Quick Diagnostic Commands

```fish
# Check all job statuses
nomad job status

# Get allocation ID for a job
nomad job status <jobname>

# View allocation details
nomad alloc status <alloc-id>

# View logs
nomad alloc logs <alloc-id>
nomad alloc logs -stderr <alloc-id>

# Check Vault integration
nomad alloc exec <alloc-id> env | grep VAULT

# Check database connectivity from container
nomad alloc exec <alloc-id> nc -zv postgresql.home 5432

# View service registration in Consul
consul catalog services
consul catalog service <service-name>
```

---

## When to Ask for Help

If you encounter:
- Services stuck in "pending" state for >5 minutes
- Repeated OOM kills after memory optimization
- Vault token issues or permission denied errors
- Persistent network connectivity failures
- Data corruption or volume mount issues

Check this guide first, then consult:
- [CHEATSHEET.md](CHEATSHEET.md) for quick reference commands
- [NEW_SERVICES_DEPLOYMENT.md](NEW_SERVICES_DEPLOYMENT.md) for architecture and service discovery
- [POSTGRESQL.md](POSTGRESQL.md) for database setup
- GitHub issues or HashiCorp community forums

---

## Future Improvements

### Needed Enhancements

1. **CNI Plugin Installation:**  
   Installing CNI plugins would enable proper bridge networking and eliminate port conflict issues.

2. **Automated Health Checks:**  
   Add alerting for services that fail health checks repeatedly.

3. **Resource Monitoring Dashboard:**  
   Create Grafana dashboard showing memory/CPU trends to identify optimization opportunities.

4. **Backup & Recovery:**  
   Document procedures for recovering from failed deployments or data corruption.

### Documentation Additions

- Add troubleshooting flowcharts for common issues
- Create a "deployment checklist" for new services
- Document rollback procedures for failed updates
- Add monitoring/alerting best practices
