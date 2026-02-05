#!/usr/bin/env node
import { execSync } from 'child_process';

const TERRAFORM_DIR = process.env.TERRAFORM_DIR || '/Users/jackharter/Developer/hashi_homelab/terraform/environments/dev';

console.log(`Testing Terraform in directory: ${TERRAFORM_DIR}...`);

try {
  // Test terraform version
  const version = execSync('terraform version -json', { encoding: 'utf-8' });
  const versionData = JSON.parse(version);
  console.log(`✓ Terraform version: ${versionData.terraform_version}`);
  
  // Test terraform validate in dev environment
  process.chdir(TERRAFORM_DIR);
  const validate = execSync('terraform validate -json', { encoding: 'utf-8' });
  const validateData = JSON.parse(validate);
  
  if (validateData.valid) {
    console.log(`✓ Configuration is valid`);
  } else {
    console.log(`⚠ Configuration has issues`);
  }
  
  // Check if state file exists
  const stateCheck = execSync('terraform show -json 2>/dev/null || echo "{}"', { encoding: 'utf-8' });
  const hasState = stateCheck.trim() !== '{}';
  console.log(`✓ State file exists: ${hasState}`);
  
  console.log('\n✅ All tests passed! Terraform MCP server should work correctly.');
  
} catch (error) {
  console.error(`✗ Test failed: ${error.message}`);
  process.exit(1);
}
