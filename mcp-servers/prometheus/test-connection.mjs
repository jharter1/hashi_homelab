import { spawn } from 'child_process';

const serverProcess = spawn('node', ['dist/index.js'], {
  stdio: ['pipe', 'pipe', 'inherit'],
  env: {
    ...process.env,
    PROMETHEUS_ADDR: process.env.PROMETHEUS_ADDR || 'http://10.0.0.60:9090',
  }
});

function sendRequest(method, params = {}) {
  const request = {
    jsonrpc: '2.0',
    id: Date.now(),
    method,
    params
  };
  serverProcess.stdin.write(JSON.stringify(request) + '\n');
}

serverProcess.stdout.on('data', (data) => {
  const lines = data.toString().split('\n').filter(line => line.trim());
  lines.forEach(line => {
    try {
      const response = JSON.parse(line);
      console.log('Response:', JSON.stringify(response, null, 2));
    } catch (e) {
      console.log('Output:', line);
    }
  });
});

setTimeout(() => {
  console.log('\n=== Testing Prometheus MCP Server ===\n');
  
  console.log('1. Initializing...');
  sendRequest('initialize', {
    protocolVersion: '2024-11-05',
    capabilities: {},
    clientInfo: {
      name: 'test-client',
      version: '1.0.0'
    }
  });

  setTimeout(() => {
    console.log('\n2. Listing tools...');
    sendRequest('tools/list');
  }, 1000);

  setTimeout(() => {
    console.log('\n3. Getting resource summary...');
    sendRequest('tools/call', {
      name: 'prometheus_resource_summary',
      arguments: {}
    });
  }, 2000);

  setTimeout(() => {
    console.log('\n4. Getting top memory containers...');
    sendRequest('tools/call', {
      name: 'prometheus_top_memory_containers',
      arguments: { limit: 5 }
    });
  }, 3000);

  setTimeout(() => {
    console.log('\n=== Test complete ===');
    serverProcess.kill();
    process.exit(0);
  }, 5000);
}, 500);
