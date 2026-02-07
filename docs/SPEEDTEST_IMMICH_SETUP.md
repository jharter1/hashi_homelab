# Speedtest & Immich Deployment Guide

## Overview

Two new services configured with Authelia SSO protection:
- **Speedtest Tracker**: Network speed monitoring with scheduled tests
- **Immich**: Self-hosted photo and video backup solution

## Prerequisites

1. Ansible must create the required NAS directories
2. Nomad clients must be reconfigured with new host volumes
3. DNS records should point to your cluster

## Step 1: Create NAS Directories

SSH to one of your Nomad clients and create the required directories:

```bash
ssh ubuntu@10.0.0.60
sudo mkdir -p /mnt/nas/speedtest
sudo mkdir -p /mnt/nas/immich/upload
sudo mkdir -p /mnt/nas/immich/postgres
sudo chown -R 1000:1000 /mnt/nas/speedtest
sudo chown -R 1000:1000 /mnt/nas/immich
```

## Step 2: Update Nomad Client Configuration

The Ansible template has been updated. Apply it to all clients:

```bash
cd ansible
ansible-playbook playbooks/site.yml --tags nomad-client
```

Or manually on each client, restart Nomad:

```bash
ssh ubuntu@10.0.0.60 "sudo systemctl restart nomad"
ssh ubuntu@10.0.0.61 "sudo systemctl restart nomad"
ssh ubuntu@10.0.0.62 "sudo systemctl restart nomad"
```

## Step 3: Deploy Services

```bash
export NOMAD_ADDR=http://10.0.0.50:4646

# Deploy Speedtest Tracker
nomad job run jobs/services/speedtest.nomad.hcl

# Deploy Immich
nomad job run jobs/services/immich.nomad.hcl
```

## Step 4: Verify Deployment

```bash
# Check job status
nomad job status speedtest
nomad job status immich

# Check Consul registration
consul catalog services | grep -E "speedtest|immich"

# View logs if needed
nomad alloc logs -f <allocation-id>
```

## Step 5: Access Services

Both services are protected by Authelia and accessible via:

- **Speedtest Tracker**: https://speedtest.lab.hartr.net
  - First login will create admin account
  - Configure speedtest schedule in Settings
  
- **Immich**: https://immich.lab.hartr.net
  - Create admin account on first visit
  - Mobile apps available: iOS and Android
  - Use https://immich.lab.hartr.net as server URL

## Service Details

### Speedtest Tracker

**Features:**
- Automatic speed tests every 6 hours
- Historical data visualization
- Network performance trends
- SQLite database (no external DB required)

**Configuration:**
- Port: 8765
- Data: `/mnt/nas/speedtest`
- Schedule: Configurable via web UI
- Results retention: 365 days

### Immich

**Features:**
- Photo and video backup from mobile devices
- Automatic album organization
- Face recognition (optional, requires ML container)
- Duplicate detection
- Multi-user support

**Architecture:**
- PostgreSQL with pgvecto-rs extension (for ML features)
- Redis cache (dedicated instance on port 6380)
- Immich server (web UI and API)
- Microservices (thumbnail generation, metadata extraction)

**Configuration:**
- Port: 2283
- Upload storage: `/mnt/nas/immich/upload`
- Database: `/mnt/nas/immich/postgres`
- Machine Learning: Disabled (can enable separately)

**Mobile Setup:**
1. Install Immich app (iOS/Android)
2. Enter server URL: `https://immich.lab.hartr.net`
3. Login with your credentials
4. Enable automatic backup

## Troubleshooting

### Speedtest Tracker

**Service won't start:**
```bash
# Check logs
nomad alloc logs <alloc-id> speedtest

# Verify volume permissions
ssh ubuntu@10.0.0.60 "ls -la /mnt/nas/speedtest"
```

**Can't access web UI:**
- Verify Traefik route: Check Traefik dashboard
- Check Consul service: `consul catalog service speedtest`
- Verify Authelia is running: `nomad job status authelia`

### Immich

**Database connection failed:**
```bash
# Check PostgreSQL container logs
nomad alloc logs <alloc-id> postgres

# Verify volume permissions
ssh ubuntu@10.0.0.60 "ls -la /mnt/nas/immich/postgres"
```

**Upload fails:**
```bash
# Check upload directory permissions
ssh ubuntu@10.0.0.60 "ls -la /mnt/nas/immich/upload"

# Should be writable by user 1000
sudo chown -R 1000:1000 /mnt/nas/immich/upload
```

**Redis connection error:**
- Redis runs on port 6380 to avoid conflict with shared Redis
- Check: `nomad alloc logs <alloc-id> redis`

## Optional: Enable Immich Machine Learning

To enable ML features (face recognition, object detection):

1. Create separate job file: `jobs/services/immich-ml.nomad.hcl`
2. Add volume for ML cache
3. Configure environment in main Immich job:
   ```hcl
   IMMICH_MACHINE_LEARNING_ENABLED = "true"
   IMMICH_MACHINE_LEARNING_URL = "http://immich-ml.service.consul:3003"
   ```

## Backup Recommendations

### Speedtest Data
```bash
# Backup SQLite database
rsync -av /mnt/nas/speedtest/ backup-location/
```

### Immich Data
```bash
# Backup photos and database
rsync -av /mnt/nas/immich/ backup-location/

# Database dump (recommended)
docker exec <postgres-container> pg_dump -U postgres immich > immich-backup.sql
```

## Resource Usage

**Speedtest Tracker:**
- CPU: 200 MHz
- Memory: 256 MB
- Disk: ~100 MB (grows with test history)

**Immich:**
- CPU: 2.1 GHz total (server + microservices + DB + Redis)
- Memory: 2.1 GB total
- Disk: Depends on photo library size

## Next Steps

1. Configure Speedtest schedule in web UI
2. Set up Immich mobile apps for backup
3. Create Immich users for family members
4. Set up backup automation for both services
5. Monitor resource usage in Grafana

## Security Notes

Both services are protected by Authelia SSO:
- Multi-factor authentication enforced
- Session management via Authelia
- Automatic logout after inactivity
- Mobile apps will need to login via web browser first

For Immich mobile apps, you may need to configure Authelia to allow the API endpoints to bypass SSO for the mobile app authentication flow. Check the Authelia documentation for API exemption patterns if you encounter issues with mobile apps.
