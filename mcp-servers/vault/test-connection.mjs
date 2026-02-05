#!/usr/bin/env node
import fetch from 'node-fetch';

const VAULT_ADDR = process.env.VAULT_ADDR || 'http://10.0.0.30:8200';

console.log(`Testing connection to Vault at ${VAULT_ADDR}...`);

try {
  // Test health endpoint (no auth required)
  const response = await fetch(`${VAULT_ADDR}/v1/sys/health?standbyok=true&perfstandbyok=true`, {
    headers: { 'Accept': 'application/json' }
  });
  
  if (!response.ok) {
    console.error(`✗ Vault health check failed: ${response.status} ${response.statusText}`);
    process.exit(1);
  }
  
  const health = await response.json();
  console.log(`✓ Vault version: ${health.version}`);
  console.log(`✓ Cluster: ${health.cluster_name || 'unnamed'}`);
  console.log(`✓ Sealed: ${health.sealed}`);
  
  console.log('\n✅ All tests passed! Vault MCP server should work correctly.');
  console.log('Note: Secret operations require VAULT_TOKEN to be set.');
  
} catch (error) {
  console.error(`✗ Connection failed: ${error.message}`);
  process.exit(1);
}
