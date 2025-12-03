#!/usr/bin/env fish
#
# set-proxmox-password.fish
# Helper script to set ProxMox password for Packer builds (Fish shell version)
#
# Usage:
#   source ./set-proxmox-password.fish
#

echo "=== Set ProxMox Password ==="
echo ""
echo "This script will set the PKR_VAR_proxmox_password environment variable"
echo "for Packer builds. The password will only be set for this terminal session."
echo ""

# Prompt for password (hidden input)
read -s -P "Enter ProxMox password: " PROXMOX_PASS
echo ""

# Export the variable
set -gx PKR_VAR_proxmox_password $PROXMOX_PASS

echo ""
echo "✅ Password set for this session"
echo ""
echo "You can now run Packer builds:"
echo "  ./packer/build-single-vm.sh"
echo "  ./packer/build-nomad-server.sh proxmox-host1"
echo ""
echo "Note: The password will be cleared when you close this terminal."
