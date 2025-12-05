#!/usr/bin/env fish

# Build ISO-based Packer templates and import to Proxmox
# This creates fresh 50GB templates from Debian netinst ISO

set SCRIPT_DIR (dirname (realpath (status -f)))
set TEMPLATE_DIR "$SCRIPT_DIR/../templates/debian-iso"

# Template IDs
set CLIENT_TEMPLATE_ID 9405
set SERVER_TEMPLATE_ID 9406

# Proxmox host
set PROXMOX_HOST "pve1"
set PROXMOX_NODE "pve1"
set STORAGE "local-lvm"

echo "=== Getting Proxmox Password ==="
read -s -P "Enter Proxmox root password: " PROXMOX_PASSWORD
export PROXMOX_PASSWORD

echo ""
echo "=== Building Debian Nomad Client Template on Proxmox ==="
cd "$TEMPLATE_DIR"

# Build client template directly on Proxmox using proxmox-iso builder
packer init debian-nomad-client.pkr.hcl
packer build -var "proxmox_password=$PROXMOX_PASSWORD" debian-nomad-client.pkr.hcl

if test $status -ne 0
    echo "ERROR: Client template build failed"
    exit 1
end

echo ""
echo "=== Building Debian Nomad Server Template on Proxmox ==="

# Build server template directly on Proxmox using proxmox-iso builder
packer init debian-nomad-server.pkr.hcl
packer build -var "proxmox_password=$PROXMOX_PASSWORD" debian-nomad-server.pkr.hcl

if test $status -ne 0
    echo "ERROR: Server template build failed"
    exit 1
end

echo ""
echo "=== Verification ==="
ssh root@$PROXMOX_HOST "qm config $CLIENT_TEMPLATE_ID | grep -E '(name|scsi0|cores|memory)'"
echo ""
ssh root@$PROXMOX_HOST "qm config $SERVER_TEMPLATE_ID | grep -E '(name|scsi0|cores|memory)'"

echo ""
echo "=== Templates Created Successfully ==="
echo "Client: VM $CLIENT_TEMPLATE_ID (debian12-nomad-client)"
echo "Server: VM $SERVER_TEMPLATE_ID (debian12-nomad-server)"
