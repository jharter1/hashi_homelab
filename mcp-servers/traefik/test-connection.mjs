#!/usr/bin/env node
/**
 * Test Traefik MCP server connectivity
 */

const TRAEFIK_API = process.env.TRAEFIK_API || "http://10.0.0.60:8080";

async function testTraefikConnection() {
  try {
    console.log(`Testing connection to Traefik at ${TRAEFIK_API}...`);
    
    // Test 1: Get overview
    const overviewResponse = await fetch(`${TRAEFIK_API}/api/overview`);
    const overview = await overviewResponse.json();
    console.log("✓ Traefik version:", overview.version || "unknown");
    
    // Test 2: List routers
    const routersResponse = await fetch(`${TRAEFIK_API}/api/http/routers`);
    const routers = await routersResponse.json();
    console.log(`✓ Found ${routers.length} HTTP routers`);
    
    // Test 3: List services
    const servicesResponse = await fetch(`${TRAEFIK_API}/api/http/services`);
    const services = await servicesResponse.json();
    console.log(`✓ Found ${services.length} services`);
    
    console.log("\n✅ All tests passed! Traefik MCP server should work correctly.");
    
  } catch (error) {
    console.error("❌ Error:", error.message);
    console.error("\nTroubleshooting:");
    console.error("- Verify Traefik API is enabled (--api.insecure=true)");
    console.error("- Check TRAEFIK_API points to correct host:port");
    console.error("- Ensure Traefik is running on the cluster");
    process.exit(1);
  }
}

testTraefikConnection();
