#!/usr/bin/env fish
# Test Authelia Protection on Services
# This script checks if services are properly protected by Authelia

set services \
    grafana.lab.hartr.net \
    prometheus.lab.hartr.net \
    jenkins.lab.hartr.net \
    gitea.lab.hartr.net

echo "🔐 Testing Authelia Protection"
echo "================================"
echo ""

for service in $services
    echo -n "Testing $service... "
    
    # Follow redirects and get final status
    set response (curl -s -L -o /dev/null -w "%{http_code}:%{redirect_url}" https://$service)
    set status (echo $response | cut -d: -f1)
    set redirect (echo $response | cut -d: -f2-)
    
    if string match -q "*authelia*" $redirect
        echo "✅ PROTECTED (redirects to Authelia)"
    else if test $status -eq 200
        echo "❌ UNPROTECTED (direct access, status 200)"
    else if test $status -eq 302
        echo "⚠️  REDIRECT (but not to Authelia: $redirect)"
    else
        echo "⚠️  UNKNOWN (status: $status)"
    end
end

echo ""
echo "Testing Authelia itself..."
set status (curl -s -o /dev/null -w "%{http_code}" https://authelia.lab.hartr.net/api/health)

if test $status -eq 200
    echo "✅ Authelia is accessible (health check: $status)"
else
    echo "❌ Authelia health check failed (status: $status)"
end

echo ""
echo "Testing public services (should NOT redirect)..."
set public_services home.lab.hartr.net whoami.lab.hartr.net

for service in $public_services
    echo -n "Testing $service... "
    set response (curl -s -L -o /dev/null -w "%{http_code}:%{redirect_url}" https://$service)
    set status (echo $response | cut -d: -f1)
    set redirect (echo $response | cut -d: -f2-)
    
    if string match -q "*authelia*" $redirect
        echo "❌ INCORRECTLY PROTECTED (should be public)"
    else if test $status -eq 200
        echo "✅ PUBLIC (no auth required)"
    else
        echo "⚠️  Status: $status"
    end
end
