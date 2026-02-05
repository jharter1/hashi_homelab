#!/usr/bin/env node
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  Tool,
} from "@modelcontextprotocol/sdk/types.js";
import fetch from "node-fetch";

// Traefik API configuration
// Traefik API is typically on port 8080 (API endpoint)
const TRAEFIK_API = process.env.TRAEFIK_API || "http://10.0.0.60:8080";

interface TraefikClient {
  get(path: string): Promise<any>;
}

const createTraefikClient = (): TraefikClient => {
  return {
    async get(path: string) {
      const response = await fetch(`${TRAEFIK_API}${path}`, {
        method: "GET",
        headers: {
          "Accept": "application/json",
        },
      });
      if (!response.ok) {
        throw new Error(`Traefik API error: ${response.statusText}`);
      }
      return response.json();
    },
  };
};

const traefik = createTraefikClient();

const TOOLS: Tool[] = [
  {
    name: "traefik_overview",
    description: "Get Traefik overview including version, providers, and feature flags",
    inputSchema: {
      type: "object",
      properties: {},
    },
  },
  {
    name: "traefik_list_routers",
    description: "List all HTTP routers configured in Traefik",
    inputSchema: {
      type: "object",
      properties: {
        status: {
          type: "string",
          description: "Filter by status: 'enabled', 'disabled', or 'all' (default: 'all')",
        },
      },
    },
  },
  {
    name: "traefik_router_details",
    description: "Get detailed information about a specific router",
    inputSchema: {
      type: "object",
      properties: {
        router_id: {
          type: "string",
          description: "The router ID (e.g., 'grafana@consulcatalog')",
        },
      },
      required: ["router_id"],
    },
  },
  {
    name: "traefik_list_services",
    description: "List all services configured in Traefik",
    inputSchema: {
      type: "object",
      properties: {
        status: {
          type: "string",
          description: "Filter by status: 'enabled', 'disabled', or 'all' (default: 'all')",
        },
      },
    },
  },
  {
    name: "traefik_service_details",
    description: "Get detailed information about a specific service",
    inputSchema: {
      type: "object",
      properties: {
        service_id: {
          type: "string",
          description: "The service ID",
        },
      },
      required: ["service_id"],
    },
  },
  {
    name: "traefik_list_middlewares",
    description: "List all middlewares configured in Traefik",
    inputSchema: {
      type: "object",
      properties: {
        status: {
          type: "string",
          description: "Filter by status: 'enabled', 'disabled', or 'all' (default: 'all')",
        },
      },
    },
  },
  {
    name: "traefik_entrypoints",
    description: "List all entrypoints (ports) configured in Traefik",
    inputSchema: {
      type: "object",
      properties: {},
    },
  },
  {
    name: "traefik_tcp_routers",
    description: "List all TCP routers (for non-HTTP traffic)",
    inputSchema: {
      type: "object",
      properties: {},
    },
  },
];

const server = new Server(
  {
    name: "traefik-mcp-server",
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
      case "traefik_overview": {
        const overview = await traefik.get("/api/overview");
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(overview, null, 2),
            },
          ],
        };
      }

      case "traefik_list_routers": {
        const status = args?.status as string | undefined;
        let routers = await traefik.get("/api/http/routers");

        if (status && status !== "all") {
          routers = routers.filter((r: any) => r.status === status);
        }

        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(routers, null, 2),
            },
          ],
        };
      }

      case "traefik_router_details": {
        const routerId = args?.router_id as string;
        const router = await traefik.get(`/api/http/routers/${encodeURIComponent(routerId)}`);
        
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(router, null, 2),
            },
          ],
        };
      }

      case "traefik_list_services": {
        const status = args?.status as string | undefined;
        let services = await traefik.get("/api/http/services");

        if (status && status !== "all") {
          services = services.filter((s: any) => s.status === status);
        }

        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(services, null, 2),
            },
          ],
        };
      }

      case "traefik_service_details": {
        const serviceId = args?.service_id as string;
        const service = await traefik.get(`/api/http/services/${encodeURIComponent(serviceId)}`);
        
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(service, null, 2),
            },
          ],
        };
      }

      case "traefik_list_middlewares": {
        const status = args?.status as string | undefined;
        let middlewares = await traefik.get("/api/http/middlewares");

        if (status && status !== "all") {
          middlewares = middlewares.filter((m: any) => m.status === status);
        }

        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(middlewares, null, 2),
            },
          ],
        };
      }

      case "traefik_entrypoints": {
        const entrypoints = await traefik.get("/api/entrypoints");
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(entrypoints, null, 2),
            },
          ],
        };
      }

      case "traefik_tcp_routers": {
        const tcpRouters = await traefik.get("/api/tcp/routers");
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(tcpRouters, null, 2),
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
  console.error("Traefik MCP Server running on stdio");
  console.error(`Connected to Traefik API at ${TRAEFIK_API}`);
}

main().catch((error) => {
  console.error("Fatal error:", error);
  process.exit(1);
});
