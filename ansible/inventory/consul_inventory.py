#!/usr/bin/env python3
"""
Dynamic Ansible inventory sourced from the Consul catalog.

Queries /v1/catalog/nodes and groups hosts by node name convention:
  dev-nomad-server-* → nomad_servers
  dev-nomad-client-* → nomad_clients

Consul URL is read from the CONSUL_HTTP_ADDR environment variable,
falling back to http://10.0.0.50:8500.

Usage:
  ansible-playbook playbooks/site.yml -i inventory/consul_inventory.py
  ansible-playbook playbooks/site.yml -i inventory/consul_inventory.py --limit dev-nomad-client-1
  ./inventory/consul_inventory.py --list   # debug: print raw inventory JSON
"""

import json
import os
import sys
import urllib.error
import urllib.request

CONSUL_URL = os.environ.get("CONSUL_HTTP_ADDR", "http://10.0.0.50:8500").rstrip("/")


def fetch_nodes():
    url = f"{CONSUL_URL}/v1/catalog/nodes"
    try:
        with urllib.request.urlopen(url, timeout=5) as response:
            return json.loads(response.read())
    except urllib.error.URLError as e:
        print(f"ERROR: Could not reach Consul at {url}: {e}", file=sys.stderr)
        sys.exit(1)


def build_inventory(nodes):
    inventory = {
        "_meta": {"hostvars": {}},
        "nomad_servers": {"hosts": []},
        "nomad_clients": {"hosts": []},
        "nomad_cluster": {
            "children": ["nomad_servers", "nomad_clients"]
        },
    }

    for node in nodes:
        name = node["Node"]
        address = node["Address"]

        inventory["_meta"]["hostvars"][name] = {
            "ansible_host": address,
        }

        if "server" in name:
            inventory["nomad_servers"]["hosts"].append(name)
        elif "client" in name:
            inventory["nomad_clients"]["hosts"].append(name)
        # Nodes that match neither pattern are registered in Consul but not
        # managed by these playbooks (e.g. the NAS or external services).

    return inventory


def main():
    # Ansible calls the script with --list or --host <name>.
    # Returning _meta.hostvars in --list means Ansible never needs --host.
    if len(sys.argv) == 2 and sys.argv[1] == "--host":
        print("{}")
        return

    nodes = fetch_nodes()
    inventory = build_inventory(nodes)
    print(json.dumps(inventory, indent=2))


if __name__ == "__main__":
    main()
