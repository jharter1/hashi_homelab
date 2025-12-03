# Nomad Services Strategy & Ideas

This document outlines the strategy for running services on the Nomad cluster and exposing them via Traefik.

## 1. The Architecture: "The Holy Trinity"

The standard pattern for HashiCorp homelabs involves three components working together:

1. **Nomad**: Schedules and runs the application containers (Docker).
2. **Consul**: Acts as the "Phonebook". When Nomad starts a container, it registers the service (IP and Port) with Consul.
3. **Traefik**: Acts as the "Switchboard". It connects to Consul, watches for services with specific tags (e.g., `traefik.enable=true`), and automatically creates routing rules to expose them on port 80/443.

### Traffic Flow

`User` -> `Traefik (Port 80)` -> `Consul Lookup` -> `Nomad Client IP:Port` -> `Container`

## 2. Implementation Plan

### Step 1: Deploy Traefik (System Job)

Traefik should run as a `system` job (on every client) or a `service` job (on specific clients) bound to ports 80 and 443.

**Required Tags for Services:**
To expose a service, you simply add tags in the Nomad job file:

```hcl
tags = [
  "traefik.enable=true",
  "traefik.http.routers.myapp.rule=Host(`myapp.homelab.local`)",
]
```

## 3. Job Ideas

Here are some categorized ideas for what to run on your new cluster:

### 🛠️ Core Infrastructure

- **Traefik**: The ingress controller (Essential).
- **Pi-hole / AdGuard Home**: Network-wide ad blocking.
- **Homepage / Dashy**: A start page for all your services.
- **Portainer**: If you want a UI to peek at Docker containers (though Nomad UI is usually enough).

### 📊 Observability (The "LGTM" Stack)

- **Prometheus**: Metrics collection.
- **Grafana**: Dashboards for your cluster stats.
- **Loki**: Log aggregation (great for debugging Nomad jobs).

### 🏠 Home Automation

- **Home Assistant**: The brain of the smart home.
- **Mosquitto**: MQTT broker for IoT devices.
- **Zigbee2MQTT**: If you have a Zigbee USB stick passed through to a client.

### 🎬 Media & Storage

- **Jellyfin / Plex**: Media streaming.
- **Sonarr / Radarr**: Media management.
- **MinIO**: S3-compatible object storage for backups.

### 🧪 Development

- **Gitea**: Self-hosted Git repositories.
- **Drone / Woodpecker CI**: CI/CD pipelines running on Nomad.
- **Code-Server**: VS Code running in the browser.

## 4. Example: Traefik Job Configuration

We will create `nomad_jobs/system/traefik.nomad.hcl` to handle ingress.

## 5. Example: Whoami (Testing)

We will create `nomad_jobs/services/whoami.nomad.hcl` to test the routing.
