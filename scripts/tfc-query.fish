#!/usr/bin/env fish
# Query Terraform Cloud state outputs
# Usage: 
#   scripts/tfc-query.fish vault outputs                  # List all outputs
#   scripts/tfc-query.fish vault nomad_server_tokens     # Get specific output
#   scripts/tfc-query.fish vault resources               # List all resources

set -l workspace $argv[1]
set -l query_type $argv[2]
set -l output_name $argv[3]

# Source credentials to get TF_CLOUD_TOKEN
source .credentials

if test -z "$workspace"
    echo "Usage: scripts/tfc-query.fish <workspace> <query_type> [output_name]"
    echo ""
    echo "Query types:"
    echo "  outputs       - List all outputs"
    echo "  resources     - List resources in state"
    echo "  show          - Show full state"
    echo ""
    echo "Examples:"
    echo "  scripts/tfc-query.fish vault outputs"
    echo "  scripts/tfc-query.fish vault nomad_server_tokens"
    echo "  scripts/tfc-query.fish hub resources"
    exit 1
end

if test -z "$TF_CLOUD_TOKEN"
    echo "❌ TF_CLOUD_TOKEN not set. Run: source .credentials"
    exit 1
end

set -l org "jharter1"  # Your Terraform Cloud organization

switch $query_type
    case outputs
        if test -n "$output_name"
            # Get specific output value
            echo "🔍 Fetching output: $output_name from workspace: $workspace"
            curl -s \
                -H "Authorization: Bearer $TF_CLOUD_TOKEN" \
                -H "Content-Type: application/vnd.api+json" \
                "https://app.terraform.io/api/v2/organizations/$org/workspaces/$workspace/current-state-version?include=outputs" \
                | python3 -c "
import sys, json
data = json.load(sys.stdin)
outputs = {o['attributes']['name']: o['attributes'] for o in data.get('included', [])}
if '$output_name' in outputs:
    out = outputs['$output_name']
    if out.get('sensitive'):
        print(f\"⚠️  Output '{$output_name}' is marked sensitive\")
        print(f\"Value: {out.get('value', 'N/A')}\")
    else:
        print(json.dumps(out.get('value'), indent=2))
else:
    print(f\"❌ Output '{$output_name}' not found\")
    print(f\"Available outputs: {', '.join(outputs.keys())}\")"
        else
            # List all outputs
            echo "📋 Listing all outputs from workspace: $workspace"
            curl -s \
                -H "Authorization: Bearer $TF_CLOUD_TOKEN" \
                -H "Content-Type: application/vnd.api+json" \
                "https://app.terraform.io/api/v2/organizations/$org/workspaces/$workspace/current-state-version?include=outputs" \
                | python3 -c "
import sys, json
data = json.load(sys.stdin)
outputs = data.get('included', [])
if outputs:
    print('Outputs:')
    for o in outputs:
        name = o['attributes']['name']
        sensitive = '🔒' if o['attributes'].get('sensitive') else '  '
        print(f'  {sensitive} {name}')
else:
    print('No outputs found')"
        end

    case resources
        echo "📦 Listing resources from workspace: $workspace"
        curl -s \
            -H "Authorization: Bearer $TF_CLOUD_TOKEN" \
            -H "Content-Type: application/vnd.api+json" \
            "https://app.terraform.io/api/v2/organizations/$org/workspaces/$workspace/current-state-version" \
            | python3 -c "
import sys, json
data = json.load(sys.stdin)
state_url = data['data']['attributes']['hosted-state-download-url']
import urllib.request
state = json.loads(urllib.request.urlopen(state_url).read())
resources = state.get('resources', [])
print(f'Total resources: {len(resources)}')
for r in resources:
    print(f'  - {r[\"type\"]}.{r[\"name\"]} ({r[\"mode\"]})')
"
    
    case show
        echo "📄 Fetching full state from workspace: $workspace"
        curl -s \
            -H "Authorization: Bearer $TF_CLOUD_TOKEN" \
            -H "Content-Type: application/vnd.api+json" \
            "https://app.terraform.io/api/v2/organizations/$org/workspaces/$workspace/current-state-version" \
            | python3 -c "
import sys, json
data = json.load(sys.stdin)
state_url = data['data']['attributes']['hosted-state-download-url']
import urllib.request
state = json.loads(urllib.request.urlopen(state_url).read())
print(json.dumps(state, indent=2))
"
    
    case '*'
        echo "❌ Unknown query type: $query_type"
        echo "Valid types: outputs, resources, show"
        exit 1
end
