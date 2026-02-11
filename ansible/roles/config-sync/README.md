# Config-Sync Role

Synchronizes configuration files from the local repository to `/mnt/nas/configs/` on Nomad clients.

## Purpose

This role replaces HEREDOC template blocks in Nomad job files with external configuration files stored on shared NAS storage. This improves:
- **Maintainability:** Edit configs with syntax highlighting, separate from HCL
- **Validation:** Tools like yamllint, promtool can validate configs before deployment
- **Version Control:** Config changes are clearly visible in git diffs
- **Deployment:** Change configs without touching job files

## Requirements

### Remote Host Requirements
- **rsync** must be installed: `apt-get install rsync`
- **User must be in nomad group:** `usermod -a -G nomad ubuntu`
- **Permissions:** `/mnt/nas/configs` must be group-writable (775)

### Local Requirements
- **rsync** must be installed on control machine (macOS usually has it)
- **SSH access** to target host without password (SSH keys)

## Usage

### Via Taskfile (Recommended)
```fish
task configs:sync
```

### Direct Ansible
```fish
cd ansible
ansible-playbook playbooks/sync-configs.yml
```

## How It Works

1. **Creates directory structure** on `/mnt/nas/configs/` with proper ownership (nomad:nomad)
2. **Syncs all config files** from local `configs/` directory to NAS
3. **Uses group permissions** instead of sudo for write access
4. **Skips metadata preservation** to work around NFS limitations

## Directory Structure

```
/mnt/nas/configs/
├── auth/
│   ├── authelia/
│   └── redis/
├── databases/
│   ├── mariadb/init-scripts/
│   └── postgresql/init-scripts/
├── infrastructure/
│   ├── minio/
│   └── traefik/
│       └── traefik.yml           # Traefik static config
└── observability/
    ├── alertmanager/
    │   └── alertmanager.yml      # Alertmanager rules
    ├── alloy/
    ├── grafana/
    │   ├── dashboards.yml         # Dashboard provisioning
    │   └── datasources.yml        # Datasource config
    ├── loki/
    │   └── loki.yaml              # Loki configuration
    └── prometheus/
        └── prometheus.yml         # Prometheus scrape configs
```

## Configuration

### Excluded Patterns
The following patterns are excluded from sync:
- `.git` - Git metadata
- `README.md` - Documentation files
- `*.swp` - Vim swap files

Add more exclusions in `tasks/main.yml` if needed.

### rsync Options
```yaml
rsync_opts:
  - "--exclude=.git"
  - "--exclude=README.md"
  - "--exclude=*.swp"
  - "--omit-dir-times"   # Don't set directory timestamps (NFS limitation)
  - "--no-perms"         # Don't preserve permissions (handled by directory)
  - "--no-owner"         # Don't set file owner (handled by directory)
  - "--no-group"         # Don't set file group (handled by directory)
```

These options work around NFS limitations where non-owner users can't modify metadata.

## Troubleshooting

### Permission Denied Errors

**Symptom:**
```
rsync: failed to set permissions on "/mnt/nas/configs/...": Operation not permitted
```

**Solution:**
1. Check ubuntu user is in nomad group:
   ```bash
   ssh ubuntu@10.0.0.60 "groups ubuntu | grep nomad"
   ```

2. Add user to group if missing:
   ```bash
   ssh ubuntu@10.0.0.60 "sudo usermod -a -G nomad ubuntu"
   ```

3. Check directory permissions:
   ```bash
   ssh ubuntu@10.0.0.60 "ls -la /mnt/nas/configs/"
   # Should show: drwxrwxr-x nomad nomad
   ```

4. Fix permissions if needed:
   ```bash
   ssh ubuntu@10.0.0.60 "sudo chmod 775 /mnt/nas/configs && sudo chmod -R 775 /mnt/nas/configs/*"
   ```

### rsync Command Not Found

**Symptom:**
```
bash: line 1: rsync: command not found
```

**Solution:**
Install rsync on the target host:
```bash
ssh ubuntu@10.0.0.60 "sudo apt-get update && sudo apt-get install -y rsync"
```

**Permanent Fix:**
Add rsync to `ansible/roles/base-system/tasks/main.yml`:
```yaml
- name: Install essential utilities
  apt:
    name:
      - rsync
    state: present
  become: yes
```

### Become/Sudo Errors on macOS

**Symptom:**
```
[ERROR]: Task failed: sudo: a password is required
```

**Cause:**
Global `become = True` in `ansible.cfg` is trying to run sudo on your Mac for the `synchronize` task with `delegate_to: localhost`.

**Solution:**
The role explicitly sets `become: no` for the sync task. This should not occur with current code.

## Handlers

The role defines handlers for restarting services when configs change:
- `restart traefik`
- `restart prometheus`
- `restart grafana`
- `restart loki`
- `restart alertmanager`
- `restart alloy`

**Note:** Handlers are currently NOT triggered by the bulk sync task. Services must be restarted manually with `nomad job run` after config changes.

## Dependencies

- **base-system** role (for NFS mounts and user configuration)

## Tags

None currently defined. Can be added if needed:
```yaml
roles:
  - role: config-sync
    tags: ['config', 'sync']
```

## Variables

None. Role uses playbook-relative paths and hardcoded destinations.

## Future Enhancements

1. **Add validation step** - Run yamllint, promtool, etc. before sync
2. **Automatic service restart** - Trigger handlers based on changed files
3. **Rollback mechanism** - Keep previous config versions for quick rollback
4. **Sync verification** - Check files exist and are readable after sync
5. **Dry-run mode** - Show what would be synced without actually syncing

## Related Documentation

- [Phase 1 Lessons Learned](../../docs/PHASE1_LESSONS_LEARNED.md) - Issues encountered and solutions
- [Phase 1 Testing Guide](../../docs/PHASE1_TESTING_GUIDE.md) - How to test config externalization
- [Config Externalization Status](../../docs/CONFIG_EXTERNALIZATION_STATUS.md) - Which services use external configs
