# Configuration Files

> **⚠️ NOTE**: These standalone configuration files are primarily for reference. Production deployments use Ansible templates from `ansible/roles/*/templates/`.

This directory contains example HashiCorp service configurations for different deployment scenarios.

## Current Production Approach

Configuration is managed by Ansible:
- **Consul**: `ansible/roles/consul/templates/consul.hcl.j2`
- **Nomad Servers**: `ansible/roles/nomad-server/templates/nomad.hcl.j2`
- **Nomad Clients**: `ansible/roles/nomad-client/templates/nomad.hcl.j2`

Deploy configuration with: `task ansible:configure` or `ansible-playbook playbooks/site.yml`

## Reference Files

### consul-standalone.hcl

Consul configuration for standalone/single-node deployment.

**Features:**
- Runs as server with `bootstrap_expect = 1`
- Binds to all interfaces (0.0.0.0)
- UI enabled on port 8500
- Suitable for development and testing

**Usage:**
```bash
sudo cp consul-standalone.hcl /etc/consul.d/consul.hcl
sudo chown consul:consul /etc/consul.d/consul.hcl
sudo -u consul consul agent -config-dir=/etc/consul.d/
```

### nomad-client.hcl

Nomad configuration for client-only mode.

**Features:**
- Client mode only (requires separate server)
- Consul integration enabled
- raw_exec driver enabled
- Suitable for worker nodes

**Usage:**
```bash
sudo cp nomad-client.hcl /etc/nomad.d/nomad.hcl
sudo chown nomad:nomad /etc/nomad.d/nomad.hcl
sudo -u nomad nomad agent -config=/etc/nomad.d/
```

**Note:** Requires a Nomad server to be available.

### nomad-dev.hcl

Nomad configuration for standalone/development mode.

**Features:**
- Both server and client mode
- `bootstrap_expect = 1` for single-node
- Consul integration enabled
- raw_exec driver enabled
- Suitable for development and testing

**Usage:**
```bash
sudo cp nomad-dev.hcl /etc/nomad.d/nomad.hcl
sudo chown nomad:nomad /etc/nomad.d/nomad.hcl
sudo -u nomad nomad agent -config=/etc/nomad.d/
```

**Recommended for:** Single-node testing, development environments

## Deployment Scenarios

### Single Node (Development/Testing)

Use `consul-standalone.hcl` + `nomad-dev.hcl`:

```bash
# Consul
sudo cp consul-standalone.hcl /etc/consul.d/consul.hcl
sudo chown consul:consul /etc/consul.d/consul.hcl
sudo -u consul nohup consul agent -config-dir=/etc/consul.d/ > /tmp/consul.log 2>&1 &

# Nomad
sudo cp nomad-dev.hcl /etc/nomad.d/nomad.hcl
sudo chown nomad:nomad /etc/nomad.d/nomad.hcl
sudo -u nomad nohup nomad agent -config=/etc/nomad.d/ > /tmp/nomad.log 2>&1 &
```

### Multi-Node Cluster (Future)

**Consul Servers:** Modify `consul-standalone.hcl` with:
- `bootstrap_expect = 3` (for 3-node cluster)
- `retry_join` addresses

**Nomad Servers:** Create separate server config with:
- `server { enabled = true, bootstrap_expect = 3 }`
- `retry_join` addresses

**Nomad Clients:** Use `nomad-client.hcl` with:
- Server addresses configured

## Configuration Tips

1. **Always set proper ownership:**
   ```bash
   sudo chown consul:consul /etc/consul.d/*.hcl
   sudo chown nomad:nomad /etc/nomad.d/*.hcl
   ```

2. **Validate before starting:**
   ```bash
   consul validate /etc/consul.d/consul.hcl
   nomad config validate /etc/nomad.d/nomad.hcl
   ```

3. **Check logs if services fail:**
   ```bash
   tail -f /tmp/consul.log
   tail -f /tmp/nomad.log
   ```

4. **For production:** Add TLS configuration, ACLs, and proper bind addresses

## See Also

- [HashiCorp Installation Guide](../docs/HASHICORP_INSTALLATION.md)
- [Testing HashiCorp](../docs/TESTING_HASHICORP.md)
- [Consul Configuration Reference](https://www.consul.io/docs/agent/config)
- [Nomad Configuration Reference](https://www.nomadproject.io/docs/configuration)
