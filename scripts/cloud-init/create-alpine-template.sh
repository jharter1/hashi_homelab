#!/usr/bin/env bash
#
# create-alpine-template.sh
# Creates an Alpine cloud-init template in Proxmox with qemu-guest-agent
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
    "ALPINE_BASE_VMID"
    "ALPINE_VM_NAME"
    "ALPINE_CLOUD_IMAGE_URL"
    "PROXMOX_STORAGE"
    "ALPINE_MEMORY"
    "ALPINE_CORES"
    "NETWORK_BRIDGE"
    "NETWORK_DNS"
    "ALPINE_SSH_USERNAME"
    "SSH_PASSWORD"
)

for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var:-}" ]; then
        echo "[ERROR] Required variable ${var} is not set in .env file"
        exit 1
    fi
done

# Configuration from environment
VMID="${ALPINE_BASE_VMID}"
VM_NAME="${ALPINE_VM_NAME}"
IMAGE_URL="${ALPINE_CLOUD_IMAGE_URL}"
IMAGE_NAME="$(basename "${IMAGE_URL}")"
IMAGE_CACHE="/var/lib/vz/template/cache/${IMAGE_NAME}"
STORAGE="${PROXMOX_STORAGE}"
MEMORY="${ALPINE_MEMORY}"
CORES="${ALPINE_CORES}"
BRIDGE="${NETWORK_BRIDGE}"

# Cloud-init user configuration from environment
CI_USER="${ALPINE_SSH_USERNAME}"
CI_PASSWORD="${SSH_PASSWORD}"
CI_SSH_KEY="${SSH_PUBLIC_KEY:-}"  # Optional SSH key

echo "[INFO] Creating Alpine ${ALPINE_VERSION} cloud-init template (VMID: ${VMID})"

# Download Alpine cloud image if not cached
if [ ! -f "${IMAGE_CACHE}" ]; then
    echo "[INFO] Downloading Alpine cloud image to cache..."
    echo "[INFO] URL: ${IMAGE_URL}"
    wget --progress=bar:force "${IMAGE_URL}" -O "${IMAGE_CACHE}" 2>&1 | tee /tmp/alpine-download.log
    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        echo "[ERROR] Failed to download Alpine cloud image"
        cat /tmp/alpine-download.log
        exit 1
    fi
    echo "[INFO] Download complete"
else
    echo "[INFO] Using cached Alpine cloud image"
fi

# Copy to temp location for modification
TEMP_DIR=$(mktemp -d)
IMAGE_FILE="${TEMP_DIR}/${IMAGE_NAME}"
echo "[INFO] Copying image to temp location: ${TEMP_DIR}"
cp "${IMAGE_CACHE}" "${IMAGE_FILE}"

# Alpine cloud images come pre-configured with cloud-init
echo "[INFO] Using base Alpine cloud image (qemu-guest-agent will be installed by cloud-init)"

# Resize the disk image to 8GB
echo "[INFO] Resizing disk image to 8GB..."
qemu-img resize "${IMAGE_FILE}" 8G

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

# Create custom cloud-init config to enable password authentication
echo "[INFO] Creating custom cloud-init config for SSH..."
mkdir -p /var/lib/vz/snippets
cat > /var/lib/vz/snippets/alpine-cloudinit.yaml << EOF
#cloud-config
ssh_pwauth: true
chpasswd:
  list: |
    ${CI_USER}:${CI_PASSWORD}
  expire: false
packages:
  - qemu-guest-agent
runcmd:
  - rc-update add qemu-guest-agent default
  - rc-service qemu-guest-agent start
  - echo 'permit nopass ${CI_USER}' > /etc/doas.d/${CI_USER}.conf
EOF

qm set ${VMID} --cicustom "user=local:snippets/alpine-cloudinit.yaml"

# Add SSH key if provided
if [ -n "${CI_SSH_KEY}" ]; then
  qm set ${VMID} --sshkey "${CI_SSH_KEY}"
fi

# Enable QEMU guest agent (will be installed by cloud-init on first boot)
qm set ${VMID} --agent enabled=1

# Convert to template (do NOT boot it - let Packer boot it for the first time)
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
