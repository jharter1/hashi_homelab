#!/bin/bash
#
# Copy Nomad templates from pve2 to pve1 using backup/restore
#

set -e

BACKUP_DIR="/var/lib/vz/dump"

echo "=== Copying templates from pve2 to pve1 ==="

# Backup server template on pve2
echo "Step 1: Backing up server template (9502) on pve2..."
ssh root@10.0.0.22 "vzdump 9502 --dumpdir $BACKUP_DIR --mode snapshot --compress zstd"

# Get the backup filename
BACKUP_FILE_SERVER=$(ssh root@10.0.0.22 "ls -t $BACKUP_DIR/vzdump-qemu-9502-*.vma.zst | head -n1")
echo "Backup created: $BACKUP_FILE_SERVER"

# Copy backup to pve1
echo ""
echo "Step 2: Copying backup to pve1..."
ssh root@10.0.0.22 "scp $BACKUP_FILE_SERVER root@10.0.0.21:$BACKUP_DIR/"

# Restore on pve1 as VM 9500
echo ""
echo "Step 3: Restoring as VM 9500 on pve1..."
BACKUP_FILENAME=$(basename "$BACKUP_FILE_SERVER")
ssh root@10.0.0.21 "qmrestore $BACKUP_DIR/$BACKUP_FILENAME 9500 --storage local-lvm"

# Clean up backup files
echo ""
echo "Step 4: Cleaning up backup files..."
ssh root@10.0.0.22 "rm -f $BACKUP_FILE_SERVER"
ssh root@10.0.0.21 "rm -f $BACKUP_DIR/$BACKUP_FILENAME"

# Backup client template on pve2
echo ""
echo "Step 5: Backing up client template (9503) on pve2..."
ssh root@10.0.0.22 "vzdump 9503 --dumpdir $BACKUP_DIR --mode snapshot --compress zstd"

# Get the backup filename
BACKUP_FILE_CLIENT=$(ssh root@10.0.0.22 "ls -t $BACKUP_DIR/vzdump-qemu-9503-*.vma.zst | head -n1")
echo "Backup created: $BACKUP_FILE_CLIENT"

# Copy backup to pve1
echo ""
echo "Step 6: Copying backup to pve1..."
ssh root@10.0.0.22 "scp $BACKUP_FILE_CLIENT root@10.0.0.21:$BACKUP_DIR/"

# Restore on pve1 as VM 9501
echo ""
echo "Step 7: Restoring as VM 9501 on pve1..."
BACKUP_FILENAME_CLIENT=$(basename "$BACKUP_FILE_CLIENT")
ssh root@10.0.0.21 "qmrestore $BACKUP_DIR/$BACKUP_FILENAME_CLIENT 9501 --storage local-lvm"

# Clean up backup files
echo ""
echo "Step 8: Cleaning up backup files..."
ssh root@10.0.0.22 "rm -f $BACKUP_FILE_CLIENT"
ssh root@10.0.0.21 "rm -f $BACKUP_DIR/$BACKUP_FILENAME_CLIENT"

# Verify templates on pve1
echo ""
echo "Step 9: Verifying templates on pve1..."
ssh root@10.0.0.21 "qm list | grep -E '9500|9501'"

echo ""
echo "=== Templates copied successfully! ==="
echo "VM 9500: debian12-nomad-server"
echo "VM 9501: debian12-nomad-client"
