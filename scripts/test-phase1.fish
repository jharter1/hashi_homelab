#!/usr/bin/env fish
# Phase 1 Testing Script - Automated validation of config externalization
# Usage: ./scripts/test-phase1.fish

set -g FAILED 0
set -g NOMAD_ADDR "http://10.0.0.50:4646"

function log_step
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║ $argv"
    echo "╚════════════════════════════════════════════════════════════════╝"
end

function check_result
    if test $status -eq 0
        echo "  ✅ $argv[1]"
    else
        echo "  ❌ $argv[1]"
        set -g FAILED 1
    end
end

log_step "Step 1: Pre-flight Validation"

echo "Checking cluster connectivity..."
nomad node status > /dev/null 2>&1
check_result "Nomad accessible"

consul members > /dev/null 2>&1
check_result "Consul accessible"

echo "Checking NAS mount..."
ssh -o ConnectTimeout=5 ubuntu@10.0.0.60 "test -d /mnt/nas" 2>/dev/null
check_result "NAS mounted on client-1"

log_step "Step 2: Running Local Validation"

task validate:all
check_result "Local validation suite passed"

log_step "Step 3: Syncing Configs to Cluster"

task configs:sync
check_result "Config sync completed"

echo "Verifying config files on NAS..."
for config in \
    infrastructure/traefik/traefik.yml \
    observability/prometheus/prometheus.yml \
    observability/grafana/datasources.yml \
    observability/grafana/dashboards.yml \
    observability/loki/loki.yaml \
    observability/alertmanager/alertmanager.yml
    
    ssh ubuntu@10.0.0.60 "test -f /mnt/nas/configs/$config" 2>/dev/null
    check_result "$config exists on NAS"
end

log_step "Step 4: Validating Nomad Jobs"

for job in \
    jobs/system/traefik.nomad.hcl \
    jobs/services/observability/prometheus/prometheus.nomad.hcl \
    jobs/services/observability/grafana/grafana.nomad.hcl \
    jobs/services/observability/loki/loki.nomad.hcl \
    jobs/services/observability/alertmanager/alertmanager.nomad.hcl
    
    nomad job validate $job > /dev/null 2>&1
    check_result (basename $job)
end

log_step "Step 5: Service Health Checks"

echo "NOTE: This assumes services are already deployed."
echo "If not deployed yet, skip this section and deploy manually."
echo ""

# Check if services are running
for service in traefik prometheus grafana loki alertmanager
    set alloc_status (nomad job status $service 2>/dev/null | grep -E "running|pending" | wc -l | tr -d ' ')
    if test $alloc_status -gt 0
        echo "  ✅ $service job exists"
    else
        echo "  ⚠️  $service not deployed (will need manual deployment)"
    end
end

log_step "Summary"

if test $FAILED -eq 0
    echo "🎉 All validation checks passed!"
    echo ""
    echo "Next steps:"
    echo "  1. Deploy services: task deploy:system && task deploy:services"
    echo "  2. Run integration tests: task test:services"
    echo "  3. Check detailed guide: docs/PHASE1_TESTING_GUIDE.md"
    exit 0
else
    echo "❌ Some checks failed. Review errors above."
    echo ""
    echo "See docs/PHASE1_TESTING_GUIDE.md for troubleshooting."
    exit 1
end
