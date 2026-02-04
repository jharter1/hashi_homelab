#!/usr/bin/env fish
# Quick setup script for Nomad MCP Server
# Run this after cloning the repository

set MCP_DIR (dirname (status -f))
set REPO_ROOT (dirname $MCP_DIR)

echo "🚀 Setting up Nomad MCP Server..."
echo ""

# Step 1: Install dependencies
echo "📦 Installing dependencies..."
cd $MCP_DIR/nomad
npm install

# Step 2: Build the server
echo "🔨 Building TypeScript..."
npm run build

# Step 3: Test connectivity
echo "🔍 Testing Nomad connectivity..."
node test-connection.mjs

echo ""
echo "✅ Setup complete!"
echo ""
echo "Next steps:"
echo "1. Add MCP config to your AI assistant settings"
echo "2. See QUICKSTART.md for configuration details"
echo "3. Try asking: 'What jobs are running in Nomad?'"
echo ""
echo "Config snippet:"
echo '  "nomad": {'
echo '    "command": "node",'
echo "    \"args\": [\"$MCP_DIR/nomad/dist/index.js\"],"
echo '    "env": { "NOMAD_ADDR": "http://10.0.0.50:4646" }'
echo '  }'
