#!/usr/bin/env node
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  Tool,
} from "@modelcontextprotocol/sdk/types.js";
import fetch from "node-fetch";
import https from "https";

// Disable SSL verification for homelab use
const httpsAgent = new https.Agent({
  rejectUnauthorized: false
});

const PROXMOX_HOST = process.env.PROXMOX_HOST || "https://10.0.0.21:8006";
const PROXMOX_USER = process.env.PROXMOX_USER || "root@pam";
const PROXMOX_PASSWORD = process.env.PROXMOX_PASSWORD || "";
const PROXMOX_TOKEN_ID = process.env.PROXMOX_TOKEN_ID || "";
const PROXMOX_TOKEN_SECRET = process.env.PROXMOX_TOKEN_SECRET || "";

interface ProxmoxClient {
  get(path: string): Promise<any>;
  post(path: string, body?: any): Promise<any>;
}

let authTicket = "";
let csrfToken = "";

const createProxmoxClient = (): ProxmoxClient => {
  async function authenticate() {
    if (PROXMOX_TOKEN_ID && PROXMOX_TOKEN_SECRET) {
      // Using API token
      return;
    }

    if (!PROXMOX_PASSWORD) {
      throw new Error("PROXMOX_PASSWORD or PROXMOX_TOKEN_ID/SECRET required");
    }

    const response = await fetch(`${PROXMOX_HOST}/api2/json/access/ticket`, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: `username=${PROXMOX_USER}&password=${encodeURIComponent(PROXMOX_PASSWORD)}`,
      agent: httpsAgent,
    });

    if (!response.ok) {
      throw new Error(`Authentication failed: ${response.statusText}`);
    }

    const data: any = await response.json();
    authTicket = data.data.ticket;
    csrfToken = data.data.CSRFPreventionToken;
  }

  function getHeaders(): Record<string, string> {
    if (PROXMOX_TOKEN_ID && PROXMOX_TOKEN_SECRET) {
      return {
        "Authorization": `PVEAPIToken=${PROXMOX_TOKEN_ID}=${PROXMOX_TOKEN_SECRET}`,
      };
    }
    return {
      "Cookie": `PVEAuthCookie=${authTicket}`,
      "CSRFPreventionToken": csrfToken,
    };
  }

  return {
    async get(path: string) {
      if (!authTicket && !PROXMOX_TOKEN_ID) {
        await authenticate();
      }

      const response = await fetch(`${PROXMOX_HOST}${path}`, {
        method: "GET",
        headers: getHeaders(),
        agent: httpsAgent,
      });

      if (!response.ok) {
        throw new Error(`Proxmox API error: ${response.statusText}`);
      }

      return response.json();
    },

    async post(path: string, body?: any) {
      if (!authTicket && !PROXMOX_TOKEN_ID) {
        await authenticate();
      }

      const response = await fetch(`${PROXMOX_HOST}${path}`, {
        method: "POST",
        headers: {
          ...getHeaders(),
          "Content-Type": "application/x-www-form-urlencoded",
        },
        body: body ? new URLSearchParams(body).toString() : undefined,
        agent: httpsAgent,
      });

      if (!response.ok) {
        const text = await response.text();
        throw new Error(`Proxmox API error: ${response.statusText} - ${text}`);
      }

      return response.json();
    },
  };
};

const proxmox = createProxmoxClient();

const TOOLS: Tool[] = [
  {
    name: "proxmox_cluster_status",
    description: "Get overall cluster status and resources",
    inputSchema: {
      type: "object",
      properties: {},
    },
  },
  {
    name: "proxmox_list_nodes",
    description: "List all nodes in the Proxmox cluster",
    inputSchema: {
      type: "object",
      properties: {},
    },
  },
  {
    name: "proxmox_node_status",
    description: "Get detailed status of a specific node",
    inputSchema: {
      type: "object",
      properties: {
        node: {
          type: "string",
          description: "Node name (e.g., 'pve1')",
        },
      },
      required: ["node"],
    },
  },
  {
    name: "proxmox_list_vms",
    description: "List all VMs across the cluster or on a specific node",
    inputSchema: {
      type: "object",
      properties: {
        node: {
          type: "string",
          description: "Node name to filter by (optional)",
        },
      },
    },
  },
  {
    name: "proxmox_vm_status",
    description: "Get detailed status of a specific VM",
    inputSchema: {
      type: "object",
      properties: {
        node: {
          type: "string",
          description: "Node name where VM resides",
        },
        vmid: {
          type: "number",
          description: "VM ID",
        },
      },
      required: ["node", "vmid"],
    },
  },
  {
    name: "proxmox_vm_config",
    description: "Get VM configuration",
    inputSchema: {
      type: "object",
      properties: {
        node: {
          type: "string",
          description: "Node name",
        },
        vmid: {
          type: "number",
          description: "VM ID",
        },
      },
      required: ["node", "vmid"],
    },
  },
  {
    name: "proxmox_storage_status",
    description: "Get storage status across the cluster",
    inputSchema: {
      type: "object",
      properties: {
        node: {
          type: "string",
          description: "Node name (optional)",
        },
      },
    },
  },
];

const server = new Server(
  {
    name: "proxmox-mcp-server",
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
      case "proxmox_cluster_status": {
        const status = await proxmox.get("/api2/json/cluster/status");
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(status.data, null, 2),
            },
          ],
        };
      }

      case "proxmox_list_nodes": {
        const nodes = await proxmox.get("/api2/json/nodes");
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(nodes.data, null, 2),
            },
          ],
        };
      }

      case "proxmox_node_status": {
        const node = args?.node as string;
        const status = await proxmox.get(`/api2/json/nodes/${node}/status`);
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(status.data, null, 2),
            },
          ],
        };
      }

      case "proxmox_list_vms": {
        const node = args?.node as string | undefined;

        if (node) {
          const vms = await proxmox.get(`/api2/json/nodes/${node}/qemu`);
          return {
            content: [
              {
                type: "text",
                text: JSON.stringify(vms.data, null, 2),
              },
            ],
          };
        } else {
          const nodes = await proxmox.get("/api2/json/nodes");
          const allVMs = [];

          for (const nodeData of nodes.data) {
            const vms = await proxmox.get(`/api2/json/nodes/${nodeData.node}/qemu`);
            allVMs.push(...vms.data.map((vm: any) => ({ ...vm, node: nodeData.node })));
          }

          return {
            content: [
              {
                type: "text",
                text: JSON.stringify(allVMs, null, 2),
              },
            ],
          };
        }
      }

      case "proxmox_vm_status": {
        const node = args?.node as string;
        const vmid = args?.vmid as number;

        const status = await proxmox.get(`/api2/json/nodes/${node}/qemu/${vmid}/status/current`);
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(status.data, null, 2),
            },
          ],
        };
      }

      case "proxmox_vm_config": {
        const node = args?.node as string;
        const vmid = args?.vmid as number;

        const config = await proxmox.get(`/api2/json/nodes/${node}/qemu/${vmid}/config`);
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(config.data, null, 2),
            },
          ],
        };
      }

      case "proxmox_storage_status": {
        const node = args?.node as string | undefined;

        if (node) {
          const storage = await proxmox.get(`/api2/json/nodes/${node}/storage`);
          return {
            content: [
              {
                type: "text",
                text: JSON.stringify(storage.data, null, 2),
              },
            ],
          };
        } else {
          const storage = await proxmox.get("/api2/json/storage");
          return {
            content: [
              {
                type: "text",
                text: JSON.stringify(storage.data, null, 2),
              },
            ],
          };
        }
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
  console.error("Proxmox MCP Server running on stdio");
  console.error(`Connected to Proxmox at ${PROXMOX_HOST}`);
}

main().catch((error) => {
  console.error("Fatal error:", error);
  process.exit(1);
});
