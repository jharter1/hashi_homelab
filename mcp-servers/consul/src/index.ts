#!/usr/bin/env node
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  Tool,
} from "@modelcontextprotocol/sdk/types.js";
import fetch from "node-fetch";

const CONSUL_ADDR = process.env.CONSUL_ADDR || "http://10.0.0.50:8500";
const CONSUL_TOKEN = process.env.CONSUL_TOKEN || "";

interface ConsulClient {
  get(path: string): Promise<any>;
  put(path: string, body?: any): Promise<any>;
  delete(path: string): Promise<any>;
}

const createConsulClient = (): ConsulClient => {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
  };
  
  if (CONSUL_TOKEN) {
    headers["X-Consul-Token"] = CONSUL_TOKEN;
  }

  return {
    async get(path: string) {
      const response = await fetch(`${CONSUL_ADDR}${path}`, {
        method: "GET",
        headers,
      });
      if (!response.ok) {
        throw new Error(`Consul API error: ${response.statusText}`);
      }
      return response.json();
    },

    async put(path: string, body?: any) {
      const response = await fetch(`${CONSUL_ADDR}${path}`, {
        method: "PUT",
        headers,
        body: typeof body === "string" ? body : JSON.stringify(body),
      });
      if (!response.ok) {
        const text = await response.text();
        throw new Error(`Consul API error: ${response.statusText} - ${text}`);
      }
      return response.json();
    },

    async delete(path: string) {
      const response = await fetch(`${CONSUL_ADDR}${path}`, {
        method: "DELETE",
        headers,
      });
      if (!response.ok) {
        throw new Error(`Consul API error: ${response.statusText}`);
      }
      return response.json();
    },
  };
};

const consul = createConsulClient();

const TOOLS: Tool[] = [
  {
    name: "consul_list_services",
    description: "List all services registered in Consul service catalog",
    inputSchema: {
      type: "object",
      properties: {},
    },
  },
  {
    name: "consul_service_health",
    description: "Get health checks and instances for a specific service",
    inputSchema: {
      type: "object",
      properties: {
        service: {
          type: "string",
          description: "The service name to query",
        },
        passing_only: {
          type: "boolean",
          description: "Only return healthy instances (default: false)",
        },
      },
      required: ["service"],
    },
  },
  {
    name: "consul_kv_get",
    description: "Get a value from Consul KV store",
    inputSchema: {
      type: "object",
      properties: {
        key: {
          type: "string",
          description: "The KV path to read",
        },
        recurse: {
          type: "boolean",
          description: "Get all keys under this prefix",
        },
      },
      required: ["key"],
    },
  },
  {
    name: "consul_kv_put",
    description: "Store a value in Consul KV store",
    inputSchema: {
      type: "object",
      properties: {
        key: {
          type: "string",
          description: "The KV path to write",
        },
        value: {
          type: "string",
          description: "The value to store",
        },
      },
      required: ["key", "value"],
    },
  },
  {
    name: "consul_kv_delete",
    description: "Delete a key from Consul KV store",
    inputSchema: {
      type: "object",
      properties: {
        key: {
          type: "string",
          description: "The KV path to delete",
        },
        recurse: {
          type: "boolean",
          description: "Delete all keys under this prefix",
        },
      },
      required: ["key"],
    },
  },
  {
    name: "consul_members",
    description: "List all Consul cluster members",
    inputSchema: {
      type: "object",
      properties: {},
    },
  },
  {
    name: "consul_leader",
    description: "Get the current Raft leader",
    inputSchema: {
      type: "object",
      properties: {},
    },
  },
];

const server = new Server(
  {
    name: "consul-mcp-server",
    version: "1.0.0",
  },
  {
    capabilities: {
      tools: {},
    },
  }
);

server.setRequestHandler(ListToolsRequestSchema, async () => {
  return { tools: TOOLS };
});

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  try {
    switch (name) {
      case "consul_list_services": {
        const services = await consul.get("/v1/catalog/services");
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(services, null, 2),
            },
          ],
        };
      }

      case "consul_service_health": {
        const service = args?.service as string;
        const passingOnly = args?.passing_only || false;
        const endpoint = passingOnly
          ? `/v1/health/service/${service}?passing`
          : `/v1/health/service/${service}`;
        
        const health = await consul.get(endpoint);
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(health, null, 2),
            },
          ],
        };
      }

      case "consul_kv_get": {
        const key = args?.key as string;
        const recurse = args?.recurse || false;
        const endpoint = recurse
          ? `/v1/kv/${key}?recurse`
          : `/v1/kv/${key}`;
        
        const data = await consul.get(endpoint);
        
        // Decode base64 values
        if (Array.isArray(data)) {
          data.forEach((item: any) => {
            if (item.Value) {
              item.DecodedValue = Buffer.from(item.Value, 'base64').toString('utf-8');
            }
          });
        } else if (data && data.Value) {
          data.DecodedValue = Buffer.from(data.Value, 'base64').toString('utf-8');
        }
        
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(data, null, 2),
            },
          ],
        };
      }

      case "consul_kv_put": {
        const key = args?.key as string;
        const value = args?.value as string;
        
        const result = await consul.put(`/v1/kv/${key}`, value);
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify({ success: result, key, value }, null, 2),
            },
          ],
        };
      }

      case "consul_kv_delete": {
        const key = args?.key as string;
        const recurse = args?.recurse || false;
        const endpoint = recurse
          ? `/v1/kv/${key}?recurse`
          : `/v1/kv/${key}`;
        
        const result = await consul.delete(endpoint);
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify({ success: result, key }, null, 2),
            },
          ],
        };
      }

      case "consul_members": {
        const members = await consul.get("/v1/agent/members");
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(members, null, 2),
            },
          ],
        };
      }

      case "consul_leader": {
        const leader = await consul.get("/v1/status/leader");
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify({ leader }, null, 2),
            },
          ],
        };
      }

      default:
        return {
          content: [
            {
              type: "text",
              text: `Unknown tool: ${name}`,
            },
          ],
          isError: true,
        };
    }
  } catch (error) {
    return {
      content: [
        {
          type: "text",
          text: `Error executing ${name}: ${error}`,
        },
      ],
      isError: true,
    };
  }
});

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("Consul MCP Server running on stdio");
  console.error(`Connected to Consul at ${CONSUL_ADDR}`);
}

main().catch((error) => {
  console.error("Fatal error:", error);
  process.exit(1);
});
