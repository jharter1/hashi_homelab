# Quick Reference

## Cluster Resource Management

### Check Nomad Cluster Memory

```fish
# Quick memory check (Fish shell)
for node_name in dev-nomad-client-1 dev-nomad-client-2 dev-nomad-client-3
  set node_id (curl -s http://10.0.0.50:4646/v1/nodes | python3 -c "import sys, json; nodes = json.load(sys.stdin); print([n['ID'] for n in nodes if '$node_name' == n['Name']][0])")
  curl -s http://10.0.0.50:4646/v1/node/$node_id | python3 -c "import sys, json; n = json.load(sys.stdin); mem = n.get('NodeResources', {}).get('Memory', {}).get('MemoryMB', 0); print('$node_name: ' + str(mem) + ' MB (' + str(round(mem/1024, 2)) + ' GB)')"
end

# Check actual VM memory
for ip in 10.0.0.60 10.0.0.61 10.0.0.62
  ssh ubuntu@$ip "echo -n '$ip: ' && free -h | grep Mem"
end
```

### Check All Job Statuses

```bash
# List all jobs and their status
curl -s http://10.0.0.50:4646/v1/jobs | python3 -c "import sys, json; jobs = json.load(sys.stdin); [print(f\"{j['Name']}: {j['Status']}\") for j in jobs]"

# Find dead services
nomad job status -address=http://10.0.0.50:4646 | grep dead
```

### Restart Services After Client Reboot

```fish
# Restart all services
for job in jobs/services/*.nomad.hcl
  nomad job run -address=http://10.0.0.50:4646 $job
end

# Or specific service
nomad job run -address=http://10.0.0.50:4646 jobs/services/homepage.nomad.hcl
```

## Vault

### Unseal all nodes

for ip in 10.0.0.30 10.0.0.31 10.0.0.32; do ssh $ip "vault operator unseal"; done

## Check status

vault status

## Nomad

### Deploy all services

nomad run jobs/services/*.nomad.hcl

## Watch job

nomad job status -verbose whoami

## Consul

### List services

consul catalog services

## DNS test

dig @10.0.0.50 whoami.service.consul