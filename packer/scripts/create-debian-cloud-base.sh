#!/bin/bash
# Script to create a base Debian 12 cloud image VM in Proxmox
# This VM will be used as the clone source for Packer builds

set -e

PROXMOX_HOST=${1:-"10.0.0.8"}
VM_ID=9400
VM_NAME="debian-12-cloud-base"
STORAGE="local-lvm"
IMAGE_URL="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
IMAGE_FILE="/tmp/debian-12-generic-amd64.qcow2"

echo "=== Creating Debian 12 Cloud Image Base VM ==="
echo "Proxmox Host: $PROXMOX_HOST"
echo "VM ID: $VM_ID"
echo "VM Name: $VM_NAME"
echo ""

# SSH into Proxmox and create the VM
ssh root@$PROXMOX_HOST << EOF
set -e

echo "Downloading Debian 12 cloud image..."
cd /tmp
wget -O $IMAGE_FILE $IMAGE_URL

echo "Creating VM $VM_ID..."
qm create $VM_ID --name $VM_NAME --memory 2048 --cores 2 --net0 virtio,bridge=vmbr0

echo "Importing disk from cloud image..."
qm importdisk $VM_ID $IMAGE_FILE $STORAGE

echo "Configuring VM to use imported disk..."
qm set $VM_ID --scsihw virtio-scsi-single --scsi0 $STORAGE:vm-$VM_ID-disk-0
qm set $VM_ID --boot order=scsi0
qm set $VM_ID --ide2 $STORAGE:cloudinit

echo "Setting cloud-init defaults..."
qm set $VM_ID --ciuser packer
qm set $VM_ID --cipassword packer
qm set $VM_ID --ipconfig0 ip=dhcp

echo "Installing QEMU guest agent..."
qm set $VM_ID --agent enabled=1

echo "Setting CPU type..."
qm set $VM_ID --cpu x86-64-v2-AES

echo "Converting to template..."
qm template $VM_ID

echo "Cleaning up..."
rm -f $IMAGE_FILE

echo ""
echo "=== Base VM created successfully ==="
echo "Template ID: $VM_ID"
echo "Template Name: $VM_NAME"
echo "You can now run Packer builds that clone this template"
EOF

echo ""
echo "Done! Template $VM_ID is ready for Packer cloning."
