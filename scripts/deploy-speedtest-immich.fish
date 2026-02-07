#!/usr/bin/env fish
# Deploy Speedtest Tracker and Immich services
# This script handles directory creation, Nomad configuration, and service deployment

set -x NOMAD_ADDR http://10.0.0.50:4646

echo "🚀 Deploying Speedtest Tracker and Immich"
echo ""

# Step 1: Create NAS directories
echo "📁 Step 1/4: Creating NAS directories..."
for client in 10.0.0.60 10.0.0.61 10.0.0.62
    echo "  Creating directories on $client..."
    ssh ubuntu@$client "sudo mkdir -p /mnt/nas/speedtest && \
                        sudo mkdir -p /mnt/nas/immich/upload && \
                        sudo mkdir -p /mnt/nas/immich/postgres && \
                        sudo chown -R 1000:1000 /mnt/nas/speedtest && \
                        sudo chown -R 1000:1000 /mnt/nas/immich"
end
echo "✅ Directories created"
echo ""

# Step 2: Update Nomad client configuration
echo "⚙️  Step 2/4: Updating Nomad client configuration..."
cd ansible
ansible-playbook playbooks/site.yml --tags nomad-client
cd ..
echo "✅ Configuration updated"
echo ""

# Step 3: Restart Nomad clients
echo "🔄 Step 3/4: Restarting Nomad clients..."
for client in 10.0.0.60 10.0.0.61 10.0.0.62
    echo "  Restarting Nomad on $client..."
    ssh ubuntu@$client "sudo systemctl restart nomad"
end
echo "  Waiting for Nomad to stabilize..."
sleep 10
echo "✅ Nomad restarted"
echo ""

# Step 4: Deploy services
echo "🎯 Step 4/4: Deploying services..."
echo "  Deploying Speedtest Tracker..."
nomad job run jobs/services/speedtest.nomad.hcl
echo ""
echo "  Deploying Immich..."
nomad job run jobs/services/immich.nomad.hcl
echo ""
echo "✅ Services deployed"
echo ""

# Verify
echo "🔍 Verifying deployment..."
sleep 5
echo ""
echo "Speedtest status:"
nomad job status speedtest
echo ""
echo "Immich status:"
nomad job status immich
echo ""

echo "✨ Deployment complete!"
echo ""
echo "Access your services:"
echo "  - Speedtest Tracker: https://speedtest.lab.hartr.net"
echo "  - Immich:            https://immich.lab.hartr.net"
echo ""
echo "Both services are protected by Authelia SSO"
echo ""
echo "📖 See docs/SPEEDTEST_IMMICH_SETUP.md for configuration details"
