#!/usr/bin/env node
import { execSync } from 'child_process';
import { existsSync } from 'fs';

const ANSIBLE_DIR = process.env.ANSIBLE_DIR || '/Users/jackharter/Developer/hashi_homelab/ansible';

console.log(`Testing Ansible in directory: ${ANSIBLE_DIR}...`);

try {
  // Test ansible version
  const version = execSync('ansible --version', { encoding: 'utf-8' });
  const versionLine = version.split('\n')[0];
  console.log(`✓ ${versionLine}`);
  
  // Check if ansible directory exists
  if (!existsSync(ANSIBLE_DIR)) {
    console.error(`✗ Ansible directory not found: ${ANSIBLE_DIR}`);
    process.exit(1);
  }
  console.log(`✓ Ansible directory exists`);
  
  // Check for inventory file
  const inventoryPath = `${ANSIBLE_DIR}/inventory/hosts.yml`;
  if (existsSync(inventoryPath)) {
    console.log(`✓ Inventory file found: ${inventoryPath}`);
  } else {
    console.log(`⚠ Default inventory not found (this is OK)`);
  }
  
  // Count playbooks
  process.chdir(ANSIBLE_DIR);
  const playbooks = execSync('find playbooks -name "*.yml" -type f 2>/dev/null | wc -l', { encoding: 'utf-8' });
  console.log(`✓ Found ${playbooks.trim()} playbooks`);
  
  // Count roles
  const roles = execSync('find roles -maxdepth 1 -type d 2>/dev/null | tail -n +2 | wc -l', { encoding: 'utf-8' });
  console.log(`✓ Found ${roles.trim()} roles`);
  
  console.log('\n✅ All tests passed! Ansible MCP server should work correctly.');
  
} catch (error) {
  console.error(`✗ Test failed: ${error.message}`);
  process.exit(1);
}
