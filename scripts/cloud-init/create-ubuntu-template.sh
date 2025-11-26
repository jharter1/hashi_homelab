#!/usr/bin/env bash
#
# create-ubuntu-template.sh
# Creates a Ubuntu cloud-init template in Proxmox with qemu-guest-agent
#

set -euo pipefail

# Load environment variables from .env file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ENV_FILE="${PROJECT_ROOT}/.env"

if [ ! -f "${ENV_FILE}" ]; then
    echo "[ERROR] .env file not found at ${ENV_FILE}"
    echo "[ERROR] Please create .env file from .env.example and configure it"
    exit 1
fi

# Source .env file
set -a
source "${ENV_FILE}"
set +a

# Validate required variables
REQUIRED_VARS=(
    "UBUNTU_BASE_VMID"
    "UBUNTU_VM_NAME"
    "UBUNTU_CLOUD_IMAGE_URL"
    "PROXMOX_STORAGE"
    "UBUNTU_MEMORY"
    "UBUNTU_CORES"
    "NETWORK_BRIDGE"
    "NETWORK_DNS"
    "SSH_USERNAME"
    "SSH_PASSWORD"
)

for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var:-}" ]; then
        echo "[ERROR] Required variable ${var} is not set in .env file"
        exit 1
    fi
done

# Configuration from environment
VMID="${UBUNTU_BASE_VMID}"
VM_NAME="${UBUNTU_VM_NAME}"
IMAGE_URL="${UBUNTU_CLOUD_IMAGE_URL}"
IMAGE_CACHE="/var/lib/vz/template/cache/$(basename "${IMAGE_URL}")"
STORAGE="${PROXMOX_STORAGE}"
MEMORY="${UBUNTU_MEMORY}"
CORES="${UBUNTU_CORES}"
BRIDGE="${NETWORK_BRIDGE}"

# Cloud-init user configuration from environment
CI_USER="${SSH_USERNAME}"
CI_PASSWORD="${SSH_PASSWORD}"
CI_SSH_KEY="${SSH_PUBLIC_KEY:-}"  # Optional SSH key

echo "[INFO] Creating Ubuntu ${UBUNTU_VERSION} cloud-init template (VMID: ${VMID})"

# Download Ubuntu cloud image if not cached
if [ ! -f "${IMAGE_CACHE}" ]; then
    echo "[INFO] Downloading Ubuntu cloud image to cache..."
    wget -q --show-progress "${IMAGE_URL}" -O "${IMAGE_CACHE}"
else
    echo "[INFO] Using cached Ubuntu cloud image"
fi

# Copy to temp location for modification
TEMP_DIR=$(mktemp -d)
IMAGE_FILE="${TEMP_DIR}/ubuntu-${UBUNTU_VERSION}-cloudimg.img"
cp "${IMAGE_CACHE}" "${IMAGE_FILE}"

# Install qemu-guest-agent and configure SSH
echo "[INFO] Installing qemu-guest-agent and configuring SSH..."
virt-customize -a "${IMAGE_FILE}" \
  --install qemu-guest-agent \
  --run-command "systemctl enable qemu-guest-agent" \
  --run-command "sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config" \
  --run-command "sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config" \
  --run-command "rm -f /etc/ssh/sshd_config.d/60-cloudimg-settings.conf" \
  --run-command "echo 'ssh_pwauth: true' >> /etc/cloud/cloud.cfg.d/99-packer.cfg"

# Resize the disk image to 10GB for additional space
echo "[INFO] Resizing disk image to 10GB..."
qemu-img resize "${IMAGE_FILE}" 10G

# Create VM
echo "[INFO] Creating VM ${VMID}..."
qm create ${VMID} \
  --name "${VM_NAME}" \
  --memory ${MEMORY} \
  --cores ${CORES} \
  --net0 virtio,bridge=${BRIDGE}

# Import disk
echo "[INFO] Importing disk..."
qm importdisk ${VMID} "${IMAGE_FILE}" ${STORAGE}

# Attach disk to VM
echo "[INFO] Configuring VM..."
qm set ${VMID} \
  --scsihw virtio-scsi-pci \
  --scsi0 ${STORAGE}:${VMID}/vm-${VMID}-disk-0.raw \
  --boot c --bootdisk scsi0 \
  --serial0 socket --vga serial0

# Add cloud-init drive
echo "[INFO] Adding cloud-init drive..."
qm set ${VMID} --ide2 ${STORAGE}:cloudinit

# Configure cloud-init
echo "[INFO] Configuring cloud-init..."
qm set ${VMID} \
  --ciuser "${CI_USER}" \
  --cipassword "${CI_PASSWORD}" \
  --ipconfig0 ip=dhcp \
  --nameserver "${NETWORK_DNS}"

# Add SSH key if provided
if [ -n "${CI_SSH_KEY}" ]; then
  qm set ${VMID} --sshkey "${CI_SSH_KEY}"
fi

# Enable QEMU guest agent
qm set ${VMID} --agent enabled=1

# Convert to template
echo "[INFO] Converting to template..."
qm template ${VMID}

# Cleanup
rm -rf "${TEMP_DIR}"

echo "[SUCCESS] Template created successfully!"
echo ""
echo "Template Details:"
echo "  VMID: ${VMID}"
echo "  Name: ${VM_NAME}"
echo "  User: ${CI_USER}"
echo "  Password: ${CI_PASSWORD}"
echo "  Guest Agent: Enabled"
echo ""
echo "You can now use this template with Packer!"
