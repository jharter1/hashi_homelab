#!/usr/bin/env node
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  Tool,
} from "@modelcontextprotocol/sdk/types.js";
import fetch from "node-fetch";

const VAULT_ADDR = process.env.VAULT_ADDR || "http://10.0.0.30:8200";
const VAULT_TOKEN = process.env.VAULT_TOKEN || "";

interface VaultClient {
  get(path: string): Promise<any>;
  post(path: string, body?: any): Promise<any>;
  list(path: string): Promise<any>;
}

const createVaultClient = (): VaultClient => {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
  };
  
  if (VAULT_TOKEN) {
    headers["X-Vault-Token"] = VAULT_TOKEN;
  }

  return {
    async get(path: string) {
      const response = await fetch(`${VAULT_ADDR}${path}`, {
        method: "GET",
        headers,
      });
      if (!response.ok) {
        throw new Error(`Vault API error: ${response.statusText}`);
      }
      return response.json();
    },

    async post(path: string, body?: any) {
      const response = await fetch(`${VAULT_ADDR}${path}`, {
        method: "POST",
        headers,
        body: body ? JSON.stringify(body) : undefined,
      });
      if (!response.ok) {
        const text = await response.text();
        throw new Error(`Vault API error: ${response.statusText} - ${text}`);
      }
      return response.json();
    },

    async list(path: string) {
      const response = await fetch(`${VAULT_ADDR}${path}?list=true`, {
        method: "GET",
        headers,
      });
      if (!response.ok) {
        throw new Error(`Vault API error: ${response.statusText}`);
      }
      return response.json();
    },
  };
};

const vault = createVaultClient();

const TOOLS: Tool[] = [
  {
    name: "vault_status",
    description: "Get Vault cluster seal status and health",
    inputSchema: {
      type: "object",
      properties: {},
    },
  },
  {
    name: "vault_read_secret",
    description: "Read a secret from Vault KV store (requires appropriate permissions)",
    inputSchema: {
      type: "object",
      properties: {
        path: {
          type: "string",
          description: "The secret path (e.g., 'secret/data/myapp')",
        },
      },
      required: ["path"],
    },
  },
  {
    name: "vault_list_secrets",
    description: "List secrets at a given path",
    inputSchema: {
      type: "object",
      properties: {
        path: {
          type: "string",
          description: "The path to list (e.g., 'secret/metadata')",
        },
      },
      required: ["path"],
    },
  },
  {
    name: "vault_write_secret",
    description: "Write a secret to Vault KV store",
    inputSchema: {
      type: "object",
      properties: {
        path: {
          type: "string",
          description: "The secret path (e.g., 'secret/data/myapp')",
        },
        data: {
          type: "object",
          description: "The secret data as key-value pairs",
        },
      },
      required: ["path", "data"],
    },
  },
  {
    name: "vault_list_policies",
    description: "List all Vault policies",
    inputSchema: {
      type: "object",
      properties: {},
    },
  },
  {
    name: "vault_read_policy",
    description: "Read a specific Vault policy",
    inputSchema: {
      type: "object",
      properties: {
        name: {
          type: "string",
          description: "The policy name",
        },
      },
      required: ["name"],
    },
  },
  {
    name: "vault_token_lookup",
    description: "Look up information about the current token",
    inputSchema: {
      type: "object",
      properties: {},
    },
  },
];

const server = new Server(
  {
    name: "vault-mcp-server",
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
      case "vault_status": {
        const [health, leader] = await Promise.all([
          vault.get("/v1/sys/health"),
          vault.get("/v1/sys/leader").catch(() => ({ leader_address: "unknown" })),
        ]);
        
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify({ health, leader }, null, 2),
            },
          ],
        };
      }

      case "vault_read_secret": {
        const path = args?.path as string;
        const secret = await vault.get(`/v1/${path}`);
        
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(secret, null, 2),
            },
          ],
        };
      }

      case "vault_list_secrets": {
        const path = args?.path as string;
        const secrets = await vault.list(`/v1/${path}`);
        
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(secrets, null, 2),
            },
          ],
        };
      }

      case "vault_write_secret": {
        const path = args?.path as string;
        const data = args?.data;
        
        const result = await vault.post(`/v1/${path}`, { data });
        
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(result, null, 2),
            },
          ],
        };
      }

      case "vault_list_policies": {
        const policies = await vault.get("/v1/sys/policies/acl");
        
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(policies, null, 2),
            },
          ],
        };
      }

      case "vault_read_policy": {
        const policyName = args?.name as string;
        const policy = await vault.get(`/v1/sys/policies/acl/${policyName}`);
        
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(policy, null, 2),
            },
          ],
        };
      }

      case "vault_token_lookup": {
        const token = await vault.get("/v1/auth/token/lookup-self");
        
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(token, null, 2),
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
  console.error("Vault MCP Server running on stdio");
  console.error(`Connected to Vault at ${VAULT_ADDR}`);
  if (!VAULT_TOKEN) {
    console.error("⚠️  Warning: VAULT_TOKEN not set. Some operations may fail.");
  }
}

main().catch((error) => {
  console.error("Fatal error:", error);
  process.exit(1);
});
