#!/usr/bin/env node
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  Tool,
} from "@modelcontextprotocol/sdk/types.js";
import fetch from "node-fetch";

// Prometheus API configuration
const PROMETHEUS_URL = process.env.PROMETHEUS_URL || "http://prometheus.home";
const PROMETHEUS_ADDR = process.env.PROMETHEUS_ADDR || "http://10.0.0.60:9090";

interface PrometheusClient {
  query(promql: string): Promise<any>;
  queryRange(promql: string, start: number, end: number, step: string): Promise<any>;
  labels(): Promise<any>;
  labelValues(label: string): Promise<any>;
}

// Create Prometheus API client
const createPrometheusClient = (): PrometheusClient => {
  const baseURL = PROMETHEUS_ADDR;

  return {
    async query(promql: string) {
      const url = `${baseURL}/api/v1/query?query=${encodeURIComponent(promql)}`;
      const response = await fetch(url);
      if (!response.ok) {
        throw new Error(`Prometheus API error: ${response.statusText}`);
      }
      return response.json();
    },

    async queryRange(promql: string, start: number, end: number, step: string) {
      const url = `${baseURL}/api/v1/query_range?query=${encodeURIComponent(promql)}&start=${start}&end=${end}&step=${step}`;
      const response = await fetch(url);
      if (!response.ok) {
        throw new Error(`Prometheus API error: ${response.statusText}`);
      }
      return response.json();
    },

    async labels() {
      const url = `${baseURL}/api/v1/labels`;
      const response = await fetch(url);
      if (!response.ok) {
        throw new Error(`Prometheus API error: ${response.statusText}`);
      }
      return response.json();
    },

    async labelValues(label: string) {
      const url = `${baseURL}/api/v1/label/${label}/values`;
      const response = await fetch(url);
      if (!response.ok) {
        throw new Error(`Prometheus API error: ${response.statusText}`);
      }
      return response.json();
    },
  };
};

const prom = createPrometheusClient();

// Define available tools
const TOOLS: Tool[] = [
  {
    name: "prometheus_container_memory",
    description: "Get current memory usage for all containers across the cluster (in MB)",
    inputSchema: {
      type: "object",
      properties: {
        container_name: {
          type: "string",
          description: "Optional: filter by container name",
        },
      },
    },
  },
  {
    name: "prometheus_container_cpu",
    description: "Get current CPU usage for all containers (percentage)",
    inputSchema: {
      type: "object",
      properties: {
        container_name: {
          type: "string",
          description: "Optional: filter by container name",
        },
      },
    },
  },
  {
    name: "prometheus_vm_memory",
    description: "Get memory usage for all VMs/nodes in the cluster",
    inputSchema: {
      type: "object",
      properties: {
        node: {
          type: "string",
          description: "Optional: filter by node name",
        },
      },
    },
  },
  {
    name: "prometheus_vm_cpu",
    description: "Get CPU usage for all VMs/nodes in the cluster",
    inputSchema: {
      type: "object",
      properties: {
        node: {
          type: "string",
          description: "Optional: filter by node name",
        },
      },
    },
  },
  {
    name: "prometheus_disk_usage",
    description: "Get disk usage across all nodes",
    inputSchema: {
      type: "object",
      properties: {
        node: {
          type: "string",
          description: "Optional: filter by node name",
        },
        mountpoint: {
          type: "string",
          description: "Optional: filter by mountpoint (e.g., /mnt/nas)",
        },
      },
    },
  },
  {
    name: "prometheus_nomad_allocations",
    description: "Get resource usage for Nomad allocations/tasks",
    inputSchema: {
      type: "object",
      properties: {
        job: {
          type: "string",
          description: "Optional: filter by job name",
        },
      },
    },
  },
  {
    name: "prometheus_query",
    description: "Execute a custom PromQL query for advanced metrics",
    inputSchema: {
      type: "object",
      properties: {
        query: {
          type: "string",
          description: "PromQL query to execute",
        },
      },
      required: ["query"],
    },
  },
  {
    name: "prometheus_top_memory_containers",
    description: "Get top N containers by memory usage",
    inputSchema: {
      type: "object",
      properties: {
        limit: {
          type: "number",
          description: "Number of top containers to return (default: 10)",
        },
      },
    },
  },
  {
    name: "prometheus_top_cpu_containers",
    description: "Get top N containers by CPU usage",
    inputSchema: {
      type: "object",
      properties: {
        limit: {
          type: "number",
          description: "Number of top containers to return (default: 10)",
        },
      },
    },
  },
  {
    name: "prometheus_resource_summary",
    description: "Get a comprehensive resource usage summary (VMs + Containers)",
    inputSchema: {
      type: "object",
      properties: {},
    },
  },
];

// Helper functions to format query results
function formatBytes(bytes: number): string {
  const mb = bytes / 1024 / 1024;
  const gb = bytes / 1024 / 1024 / 1024;
  if (gb >= 1) {
    return `${gb.toFixed(2)} GB`;
  }
  return `${mb.toFixed(2)} MB`;
}

function formatPercent(value: number): string {
  return `${(value * 100).toFixed(2)}%`;
}

// Tool handlers
async function handleToolCall(name: string, args: any) {
  switch (name) {
    case "prometheus_container_memory": {
      const filter = args.container_name
        ? `container_label_com_hashicorp_nomad_task_name=~".*${args.container_name}.*"`
        : "";
      const query = `sum by (container_label_com_hashicorp_nomad_job_name, container_label_com_hashicorp_nomad_task_name) (container_memory_usage_bytes{${filter}})`;
      const result = await prom.query(query);
      
      if (result.data.result.length === 0) {
        return { content: [{ type: "text", text: "No container memory data found" }] };
      }

      const formatted = result.data.result
        .map((item: any) => ({
          job: item.metric.container_label_com_hashicorp_nomad_job_name || "unknown",
          task: item.metric.container_label_com_hashicorp_nomad_task_name || "unknown",
          memory: formatBytes(parseFloat(item.value[1])),
          memory_bytes: parseFloat(item.value[1]),
        }))
        .sort((a: any, b: any) => b.memory_bytes - a.memory_bytes);

      return {
        content: [{
          type: "text",
          text: JSON.stringify(formatted, null, 2),
        }],
      };
    }

    case "prometheus_container_cpu": {
      const filter = args.container_name
        ? `container_label_com_hashicorp_nomad_task_name=~".*${args.container_name}.*"`
        : "";
      const query = `rate(container_cpu_usage_seconds_total{${filter}}[5m])`;
      const result = await prom.query(query);
      
      if (result.data.result.length === 0) {
        return { content: [{ type: "text", text: "No container CPU data found" }] };
      }

      const formatted = result.data.result
        .map((item: any) => ({
          job: item.metric.container_label_com_hashicorp_nomad_job_name || "unknown",
          task: item.metric.container_label_com_hashicorp_nomad_task_name || "unknown",
          cpu_usage: formatPercent(parseFloat(item.value[1])),
          cpu_cores: parseFloat(item.value[1]).toFixed(3),
        }))
        .sort((a: any, b: any) => parseFloat(b.cpu_cores) - parseFloat(a.cpu_cores));

      return {
        content: [{
          type: "text",
          text: JSON.stringify(formatted, null, 2),
        }],
      };
    }

    case "prometheus_vm_memory": {
      const filter = args.node ? `instance=~".*${args.node}.*"` : "";
      const query = `node_memory_MemTotal_bytes{${filter}} - node_memory_MemAvailable_bytes{${filter}}`;
      const result = await prom.query(query);
      
      if (result.data.result.length === 0) {
        return { content: [{ type: "text", text: "No VM memory data found" }] };
      }

      const formatted = result.data.result.map((item: any) => ({
        instance: item.metric.instance,
        used_memory: formatBytes(parseFloat(item.value[1])),
        used_bytes: parseFloat(item.value[1]),
      }));

      // Get total memory for each node
      const totalQuery = `node_memory_MemTotal_bytes{${filter}}`;
      const totalResult = await prom.query(totalQuery);
      
      const combined = formatted.map((node: any) => {
        const total = totalResult.data.result.find(
          (t: any) => t.metric.instance === node.instance
        );
        if (total) {
          const totalBytes = parseFloat(total.value[1]);
          return {
            ...node,
            total_memory: formatBytes(totalBytes),
            usage_percent: formatPercent(node.used_bytes / totalBytes),
          };
        }
        return node;
      });

      return {
        content: [{
          type: "text",
          text: JSON.stringify(combined, null, 2),
        }],
      };
    }

    case "prometheus_vm_cpu": {
      const filter = args.node ? `instance=~".*${args.node}.*"` : "";
      const query = `100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle",${filter}}[5m])) * 100)`;
      const result = await prom.query(query);
      
      if (result.data.result.length === 0) {
        return { content: [{ type: "text", text: "No VM CPU data found" }] };
      }

      const formatted = result.data.result
        .map((item: any) => ({
          instance: item.metric.instance,
          cpu_usage: formatPercent(parseFloat(item.value[1]) / 100),
        }))
        .sort((a: any, b: any) => parseFloat(b.cpu_usage) - parseFloat(a.cpu_usage));

      return {
        content: [{
          type: "text",
          text: JSON.stringify(formatted, null, 2),
        }],
      };
    }

    case "prometheus_disk_usage": {
      let filter = 'fstype!="tmpfs",fstype!="devtmpfs"';
      if (args.node) {
        filter += `,instance=~".*${args.node}.*"`;
      }
      if (args.mountpoint) {
        filter += `,mountpoint=~".*${args.mountpoint}.*"`;
      }
      
      const query = `(node_filesystem_size_bytes{${filter}} - node_filesystem_avail_bytes{${filter}}) / node_filesystem_size_bytes{${filter}}`;
      const result = await prom.query(query);
      
      if (result.data.result.length === 0) {
        return { content: [{ type: "text", text: "No disk usage data found" }] };
      }

      const formatted = result.data.result.map((item: any) => ({
        instance: item.metric.instance,
        mountpoint: item.metric.mountpoint,
        device: item.metric.device,
        usage_percent: formatPercent(parseFloat(item.value[1])),
      }));

      return {
        content: [{
          type: "text",
          text: JSON.stringify(formatted, null, 2),
        }],
      };
    }

    case "prometheus_nomad_allocations": {
      const filter = args.job ? `job=~".*${args.job}.*"` : "";
      const memQuery = `nomad_client_allocs_memory_usage{${filter}}`;
      const cpuQuery = `nomad_client_allocs_cpu_total_percent{${filter}}`;
      
      const [memResult, cpuResult] = await Promise.all([
        prom.query(memQuery),
        prom.query(cpuQuery),
      ]);

      if (memResult.data.result.length === 0) {
        return { content: [{ type: "text", text: "No Nomad allocation data found" }] };
      }

      const formatted = memResult.data.result.map((item: any) => {
        const cpu = cpuResult.data.result.find(
          (c: any) => c.metric.task === item.metric.task
        );
        return {
          job: item.metric.job,
          task: item.metric.task,
          memory: formatBytes(parseFloat(item.value[1])),
          cpu_percent: cpu ? formatPercent(parseFloat(cpu.value[1]) / 100) : "N/A",
        };
      });

      return {
        content: [{
          type: "text",
          text: JSON.stringify(formatted, null, 2),
        }],
      };
    }

    case "prometheus_query": {
      const result = await prom.query(args.query);
      return {
        content: [{
          type: "text",
          text: JSON.stringify(result.data.result, null, 2),
        }],
      };
    }

    case "prometheus_top_memory_containers": {
      const limit = args.limit || 10;
      const query = `topk(${limit}, sum by (container_label_com_hashicorp_nomad_job_name, container_label_com_hashicorp_nomad_task_name) (container_memory_usage_bytes))`;
      const result = await prom.query(query);
      
      if (result.data.result.length === 0) {
        return { content: [{ type: "text", text: "No container data found" }] };
      }

      const formatted = result.data.result.map((item: any, index: number) => ({
        rank: index + 1,
        job: item.metric.container_label_com_hashicorp_nomad_job_name || "unknown",
        task: item.metric.container_label_com_hashicorp_nomad_task_name || "unknown",
        memory: formatBytes(parseFloat(item.value[1])),
      }));

      return {
        content: [{
          type: "text",
          text: JSON.stringify(formatted, null, 2),
        }],
      };
    }

    case "prometheus_top_cpu_containers": {
      const limit = args.limit || 10;
      const query = `topk(${limit}, rate(container_cpu_usage_seconds_total[5m]))`;
      const result = await prom.query(query);
      
      if (result.data.result.length === 0) {
        return { content: [{ type: "text", text: "No container data found" }] };
      }

      const formatted = result.data.result.map((item: any, index: number) => ({
        rank: index + 1,
        job: item.metric.container_label_com_hashicorp_nomad_job_name || "unknown",
        task: item.metric.container_label_com_hashicorp_nomad_task_name || "unknown",
        cpu_usage: formatPercent(parseFloat(item.value[1])),
      }));

      return {
        content: [{
          type: "text",
          text: JSON.stringify(formatted, null, 2),
        }],
      };
    }

    case "prometheus_resource_summary": {
      // Get VM memory
      const vmMemQuery = "node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes";
      const vmMemTotal = "node_memory_MemTotal_bytes";
      const vmCpuQuery = '100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)';
      
      // Get container memory
      const containerMemQuery = "sum by (container_label_com_hashicorp_nomad_job_name) (container_memory_usage_bytes)";
      
      const [vmMem, vmMemTot, vmCpu, containerMem] = await Promise.all([
        prom.query(vmMemQuery),
        prom.query(vmMemTotal),
        prom.query(vmCpuQuery),
        prom.query(containerMemQuery),
      ]);

      const summary = {
        vms: vmMem.data.result.map((item: any) => {
          const total = vmMemTot.data.result.find((t: any) => t.metric.instance === item.metric.instance);
          const cpu = vmCpu.data.result.find((c: any) => c.metric.instance === item.metric.instance);
          return {
            instance: item.metric.instance,
            memory_used: formatBytes(parseFloat(item.value[1])),
            memory_total: total ? formatBytes(parseFloat(total.value[1])) : "N/A",
            memory_percent: total ? formatPercent(parseFloat(item.value[1]) / parseFloat(total.value[1])) : "N/A",
            cpu_usage: cpu ? formatPercent(parseFloat(cpu.value[1]) / 100) : "N/A",
          };
        }),
        containers: containerMem.data.result
          .map((item: any) => ({
            job: item.metric.container_label_com_hashicorp_nomad_job_name || "unknown",
            memory: formatBytes(parseFloat(item.value[1])),
            memory_bytes: parseFloat(item.value[1]),
          }))
          .sort((a: any, b: any) => b.memory_bytes - a.memory_bytes)
          .slice(0, 15), // Top 15 containers
      };

      return {
        content: [{
          type: "text",
          text: JSON.stringify(summary, null, 2),
        }],
      };
    }

    default:
      throw new Error(`Unknown tool: ${name}`);
  }
}

// Create and start the MCP server
const server = new Server(
  {
    name: "prometheus-mcp-server",
    version: "1.0.0",
  },
  {
    capabilities: {
      tools: {},
    },
  }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: TOOLS,
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  try {
    const result = await handleToolCall(request.params.name, request.params.arguments || {});
    return result;
  } catch (error: any) {
    return {
      content: [{
        type: "text",
        text: `Error: ${error.message}`,
      }],
      isError: true,
    };
  }
});

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("Prometheus MCP Server running on stdio");
  console.error(`Connected to: ${PROMETHEUS_ADDR}`);
}

main().catch((error) => {
  console.error("Fatal error in main():", error);
  process.exit(1);
});
