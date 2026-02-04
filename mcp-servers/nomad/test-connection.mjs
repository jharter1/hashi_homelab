#!/usr/bin/env node
/**
 * Simple test script to verify the Nomad MCP server can connect
 * and make basic API calls
 */

const NOMAD_ADDR = process.env.NOMAD_ADDR || "http://10.0.0.50:4646";

async function testNomadConnection() {
  try {
    console.log(`Testing connection to Nomad at ${NOMAD_ADDR}...`);
    
    // Test 1: Get leader
    const leaderResponse = await fetch(`${NOMAD_ADDR}/v1/status/leader`);
    const leader = await leaderResponse.text();
    console.log("✓ Leader:", leader.replace(/"/g, ''));
    
    // Test 2: List jobs
    const jobsResponse = await fetch(`${NOMAD_ADDR}/v1/jobs`);
    const jobs = await jobsResponse.json();
    console.log(`✓ Found ${jobs.length} jobs`);
    
    // Test 3: List nodes
    const nodesResponse = await fetch(`${NOMAD_ADDR}/v1/nodes`);
    const nodes = await nodesResponse.json();
    console.log(`✓ Found ${nodes.length} nodes`);
    
    console.log("\n✅ All tests passed! Nomad MCP server should work correctly.");
    console.log("\nNext steps:");
    console.log("1. Configure your AI assistant (see QUICKSTART.md)");
    console.log("2. Try asking: 'What jobs are running in Nomad?'");
    
  } catch (error) {
    console.error("❌ Error:", error.message);
    console.error("\nTroubleshooting:");
    console.error("- Verify Nomad is running");
    console.error("- Check NOMAD_ADDR is correct");
    console.error("- Ensure network connectivity");
    process.exit(1);
  }
}

testNomadConnection();
