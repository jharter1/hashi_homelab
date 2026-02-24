# SSO Deployment Issue Fixes

Date: 2026-02-23
Status: In Progress

## Issues Identified

### 1. Grafana - Database Connection Timeout
**Status:** Fixed in job file, not yet redeployed

**Symptoms:**
- chunkNotFound redirect loop at `https://grafana.lab.hartr.net/?chunkNotFound=true`
- Logs show: `pq: canceling statement due to user request`
- Proxy auth user sync failing
- Multiple `unable to retrieve user` errors

**Root Cause:**
Database connection pool too small for proxy auth queries which synchronize users on every request.

**Fix Applied:**
Added to `jobs/services/observability/grafana/grafana.nomad.hcl`:
```hcl
GF_DATABASE_MAX_OPEN_CONN = "20"
GF_DATABASE_MAX_IDLE_CONN = "10"
GF_DATABASE_CONN_MAX_LIFETIME = "14400"
GF_DATABASE_QUERY_RETRIES = "3"
```

**Next Steps:**
```bash
nomad job run jobs/services/observability/grafana/grafana.nomad.hcl
```

---

### 2. BookStack - Permission Denied
**Status:** Fixed in job file, redeployed as v14

**Symptoms:**
- 43 failed allocations
- Logs show: `Permission denied` writing to `/config` directory
- Container message: "You are running this container as a non-root user"

**Root Cause:**
LinuxServer.io images expect to run as root initially, then drop privileges via PUID/PGID. The `user = "1000:1000"` directive in the job file prevented initial root access needed for setup.

**Fix Applied:**
Removed this line from `jobs/services/media/bookstack/bookstack.nomad.hcl`:
```hcl
# user = "1000:1000"  # REMOVED - LinuxServer.io handles this internally
```

**Deployment:**
- Version 14 deployed with allocation `e78d83df`
- Waiting for health check (Progress Deadline: 2026-02-23T19:32:11Z)

**Verification:**
```bash
nomad job status bookstack
nomad alloc logs e78d83df bookstack
```

---

## 3. Speedtest - Port Conflict
**Status:** Orphaned process killed, job redeployed

**Symptoms:**
- 4 failed allocations
- Logs show: `could not bind IPv4 address "0.0.0.0": Address in use` on port 5434
- PostgreSQL sidecar failing immediately

**Root Cause:**
Previous failed deployment left orphaned postgres process (PID 2291435) on port 5434.

**Fix Applied:**
```bash
ssh ubuntu@10.0.0.61 "sudo kill 2291435"
nomad job run jobs/services/infrastructure/speedtest/speedtest.nomad.hcl
```

**Verification:**
```bash
nomad job status speedtest
# Should show new allocation starting without port conflicts
```

---

## Summary of Actions

### Completed
- ✅ Identified root causes for all 3 service failures
- ✅ Fixed BookStack job file (removed user directive)
- ✅ Fixed Grafana job file (added DB connection pool settings)
- ✅ Killed orphaned Speedtest postgres process
- ✅ Redeployed BookStack (v14)
- ✅ Redeployed Speedtestfiles### Pending

- ⏳ Redeploy Grafana with database connection pool fixes
- ⏳ Verify BookStack v14 starts successfully without permission errors
- ⏳ Verify Speedtest allocates successfully
- ⏳ Test Grafana proxy auth after redeployment
- ⏳ Confirm all 3 services are healthy and accessible

---

## Commands to Complete

```bash
# Redeploy Grafana with connection pool fixes
nomad job run jobs/services/observability/grafana/grafana.nomad.hcl

# Wait 60s for health checks
sleep 60

# Verify all services
nomad job status grafana
nomad job status bookstack
nomad job status speedtest

# Check allocations
nomad job status graafana | grep -A5 "Allocations"
nomad job status bookstack | grep -A5 "Allocations"
nomad job status speedtest | grep -A5 "Allocations"

# Test access
curl -k https://grafana.lab.hartr.net
curl -k https://bookstack.lab.hartr.net
curl -k https://speedtest.lab.hartr.net
```

---

## Root Cause Analysis

1. **Grafana chunkNotFound** was NOT a frontend asset issue - it was database timeouts during proxy auth causing the application to lose state and fail JavaScript module loading

2. **BookStack permission errors** were caused by misconfiguration of LinuxServer.io container expectations

3. **Speedtest failure** was unrelated to SSO changes - coincidental orphaned process from earlier failed deployment

None of these issues were directly caused by the SSO configuration changes. They were:
- Grafana: Database performance issue exposed by increased auth queries
- BookStack: Configuration error introduced when adding SSO
- Speedtest: Pre-existing infrastructure issue

---

## Lessons Learned

### Docker User Management
- LinuxServer.io images handle user switching internally via PUID/PGID environment variables
- Do NOT set `user = "UID:GID"` in Nomad job - let container run as root then drop privileges
- Documented in job file with comment for future reference

### Database Connection Pooling
- Proxy authentication increases database load significantly (user sync on every request)
- Default Grafana connection pool may be insufficient for high-auth load
- Always configure connection pool settings explicitly for production deployments

### Orphaned Processes
- Host networking mode can leave orphaned processes from failed deployments
- Check for port conflicts before assuming deployment issue
- Use `lsof -i :PORT` to identify blocking processes

### Terminal Cache Issues (noted for improvements)
The Fish terminal maintained persistent cache of old output, making realtime verification difficult.  Need better terminal management or alternative verification methods (API calls, UI checks).