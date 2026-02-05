#!/usr/bin/env node
/**
 * Test Consul MCP server connectivity
 */

const CONSUL_ADDR = process.env.CONSUL_ADDR || "http://10.0.0.50:8500";

async function testConsulConnection() {
  try {
    console.log(`Testing connection to Consul at ${CONSUL_ADDR}...`);
    
    // Test 1: Get leader
    const leaderResponse = await fetch(`${CONSUL_ADDR}/v1/status/leader`);
    const leader = await leaderResponse.json();
    console.log("✓ Leader:", leader);
    
    // Test 2: List services
    const servicesResponse = await fetch(`${CONSUL_ADDR}/v1/catalog/services`);
    const services = await servicesResponse.json();
    console.log(`✓ Found ${Object.keys(services).length} services`);
    
    // Test 3: Get members
    const membersResponse = await fetch(`${CONSUL_ADDR}/v1/agent/members`);
    const members = await membersResponse.json();
    console.log(`✓ Found ${members.length} cluster members`);
    
    console.log("\n✅ All tests passed! Consul MCP server should work correctly.");
    
  } catch (error) {
    console.error("❌ Error:", error.message);
    process.exit(1);
  }
}

testConsulConnection();
