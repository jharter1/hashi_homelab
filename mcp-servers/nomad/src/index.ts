#!/usr/bin/env node
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  Tool,
} from "@modelcontextprotocol/sdk/types.js";
import fetch from "node-fetch";

// Nomad API configuration
const NOMAD_ADDR = process.env.NOMAD_ADDR || "http://10.0.0.50:4646";
const NOMAD_TOKEN = process.env.NOMAD_TOKEN || "";

interface NomadClient {
  get(path: string): Promise<any>;
  post(path: string, body?: any): Promise<any>;
  delete(path: string): Promise<any>;
}

// Create Nomad API client
const createNomadClient = (): NomadClient => {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
  };
  
  if (NOMAD_TOKEN) {
    headers["X-Nomad-Token"] = NOMAD_TOKEN;
  }

  return {
    async get(path: string) {
      const response = await fetch(`${NOMAD_ADDR}${path}`, {
        method: "GET",
        headers,
      });
      if (!response.ok) {
        throw new Error(`Nomad API error: ${response.statusText}`);
      }
      return response.json();
    },

    async post(path: string, body?: any) {
      const response = await fetch(`${NOMAD_ADDR}${path}`, {
        method: "POST",
        headers,
        body: body ? JSON.stringify(body) : undefined,
      });
      if (!response.ok) {
        const text = await response.text();
        throw new Error(`Nomad API error: ${response.statusText} - ${text}`);
      }
      return response.json();
    },

    async delete(path: string) {
      const response = await fetch(`${NOMAD_ADDR}${path}`, {
        method: "DELETE",
        headers,
      });
      if (!response.ok) {
        throw new Error(`Nomad API error: ${response.statusText}`);
      }
      return response.json();
    },
  };
};

const nomad = createNomadClient();

// Define available tools
const TOOLS: Tool[] = [
  {
    name: "nomad_job_status",
    description: "Get the status of a Nomad job including allocations and task states",
    inputSchema: {
      type: "object",
      properties: {
        job_id: {
          type: "string",
          description: "The ID of the job to query",
        },
      },
      required: ["job_id"],
    },
  },
  {
    name: "nomad_list_jobs",
    description: "List all jobs in the Nomad cluster with their current status",
    inputSchema: {
      type: "object",
      properties: {
        prefix: {
          type: "string",
          description: "Optional prefix to filter jobs",
        },
      },
    },
  },
  {
    name: "nomad_allocation_logs",
    description: "Get logs from a specific Nomad allocation",
    inputSchema: {
      type: "object",
      properties: {
        alloc_id: {
          type: "string",
          description: "The allocation ID to get logs from",
        },
        task: {
          type: "string",
          description: "The task name within the allocation",
        },
        tail: {
          type: "number",
          description: "Number of lines to tail (default: 100)",
        },
        follow: {
          type: "boolean",
          description: "Follow logs (not recommended for MCP)",
        },
      },
      required: ["alloc_id", "task"],
    },
  },
  {
    name: "nomad_node_status",
    description: "Get status of all Nomad nodes (servers and clients)",
    inputSchema: {
      type: "object",
      properties: {},
    },
  },
  {
    name: "nomad_cluster_health",
    description: "Get overall cluster health including server count, client count, and job statistics",
    inputSchema: {
      type: "object",
      properties: {},
    },
  },
  {
    name: "nomad_stop_job",
    description: "Stop a running Nomad job",
    inputSchema: {
      type: "object",
      properties: {
        job_id: {
          type: "string",
          description: "The ID of the job to stop",
        },
        purge: {
          type: "boolean",
          description: "Purge the job from the system (default: false)",
        },
      },
      required: ["job_id"],
    },
  },
  {
    name: "nomad_job_allocations",
    description: "Get all allocations for a specific job",
    inputSchema: {
      type: "object",
      properties: {
        job_id: {
          type: "string",
          description: "The ID of the job",
        },
      },
      required: ["job_id"],
    },
  },
  {
    name: "nomad_allocation_status",
    description: "Get detailed status of a specific allocation",
    inputSchema: {
      type: "object",
      properties: {
        alloc_id: {
          type: "string",
          description: "The allocation ID",
        },
      },
      required: ["alloc_id"],
    },
  },
];

// Create MCP server
const server = new Server(
  {
    name: "nomad-mcp-server",
    version: "1.0.0",
  },
  {
    capabilities: {
      tools: {},
    },
  }
);

// Handle tool list requests
server.setRequestHandler(ListToolsRequestSchema, async () => {
  return { tools: TOOLS };
});

// Handle tool execution
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  try {
    switch (name) {
      case "nomad_list_jobs": {
        const jobs = await nomad.get("/v1/jobs");
        const filtered = args?.prefix
          ? jobs.filter((j: any) => j.ID.startsWith(args.prefix))
          : jobs;
        
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(filtered, null, 2),
            },
          ],
        };
      }

      case "nomad_job_status": {
        const jobId = args?.job_id as string;
        const [job, allocations] = await Promise.all([
          nomad.get(`/v1/job/${jobId}`),
          nomad.get(`/v1/job/${jobId}/allocations`),
        ]);

        return {
          content: [
            {
              type: "text",
              text: JSON.stringify({ job, allocations }, null, 2),
            },
          ],
        };
      }

      case "nomad_allocation_logs": {
        const allocId = args?.alloc_id as string;
        const task = args?.task as string;
        const tail = args?.tail || 100;

        const logs = await nomad.get(
          `/v1/client/fs/logs/${allocId}?task=${task}&type=stdout&tail=true&offset=${tail}`
        );

        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(logs, null, 2),
            },
          ],
        };
      }

      case "nomad_node_status": {
        const nodes = await nomad.get("/v1/nodes");
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(nodes, null, 2),
            },
          ],
        };
      }

      case "nomad_cluster_health": {
        const [jobs, nodes, leader] = await Promise.all([
          nomad.get("/v1/jobs"),
          nomad.get("/v1/nodes"),
          nomad.get("/v1/status/leader"),
        ]);

        const health = {
          leader,
          total_jobs: jobs.length,
          running_jobs: jobs.filter((j: any) => j.Status === "running").length,
          total_nodes: nodes.length,
          ready_nodes: nodes.filter((n: any) => n.Status === "ready").length,
        };

        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(health, null, 2),
            },
          ],
        };
      }

      case "nomad_stop_job": {
        const jobId = args?.job_id as string;
        const purge = args?.purge || false;

        const result = await nomad.delete(
          `/v1/job/${jobId}${purge ? "?purge=true" : ""}`
        );

        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(result, null, 2),
            },
          ],
        };
      }

      case "nomad_job_allocations": {
        const jobId = args?.job_id as string;
        const allocations = await nomad.get(`/v1/job/${jobId}/allocations`);

        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(allocations, null, 2),
            },
          ],
        };
      }

      case "nomad_allocation_status": {
        const allocId = args?.alloc_id as string;
        const allocation = await nomad.get(`/v1/allocation/${allocId}`);

        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(allocation, null, 2),
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

// Start the server
async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("Nomad MCP Server running on stdio");
  console.error(`Connected to Nomad at ${NOMAD_ADDR}`);
}

main().catch((error) => {
  console.error("Fatal error:", error);
  process.exit(1);
});
