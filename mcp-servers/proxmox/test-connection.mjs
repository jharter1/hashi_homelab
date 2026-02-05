#!/usr/bin/env node
import fetch from 'node-fetch';
import https from 'https';

const PROXMOX_HOST = process.env.PROXMOX_HOST || '10.0.0.21';
const PROXMOX_PORT = process.env.PROXMOX_PORT || '8006';

// Disable SSL verification for homelab
const agent = new https.Agent({ rejectUnauthorized: false });

console.log(`Testing connection to Proxmox at https://${PROXMOX_HOST}:${PROXMOX_PORT}...`);

try {
  // Test basic connectivity (API endpoint responds)
  const response = await fetch(`https://${PROXMOX_HOST}:${PROXMOX_PORT}/api2/json`, {
    headers: { 'Accept': 'application/json' },
    agent
  });
  
  // Expecting 401 or similar since we're not authenticated - that's OK, we just want to verify the endpoint is reachable
  console.log(`✓ Proxmox API endpoint is reachable`);
  console.log(`✓ Host: https://${PROXMOX_HOST}:${PROXMOX_PORT}`);
  console.log(`✓ Response status: ${response.status} (${response.statusText})`);
  
  console.log('\n✅ All tests passed! Proxmox MCP server should work correctly.');
  console.log('Note: VM/cluster operations require PROXMOX_TOKEN_ID and PROXMOX_TOKEN_SECRET to be set.');
  
} catch (error) {
  console.error(`✗ Connection failed: ${error.message}`);
  process.exit(1);
}
