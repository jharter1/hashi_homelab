#!/usr/bin/env node
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  Tool,
} from "@modelcontextprotocol/sdk/types.js";
import { exec } from "child_process";
import { promisify } from "util";
import * as path from "path";
import * as fs from "fs/promises";
import * as yaml from "js-yaml";

const execAsync = promisify(exec);

const ANSIBLE_DIR = process.env.ANSIBLE_DIR || "/Users/jackharter/Developer/hashi_homelab/ansible";

const TOOLS: Tool[] = [
  {
    name: "ansible_list_playbooks",
    description: "List all available Ansible playbooks",
    inputSchema: {
      type: "object",
      properties: {},
    },
  },
  {
    name: "ansible_list_roles",
    description: "List all available Ansible roles",
    inputSchema: {
      type: "object",
      properties: {},
    },
  },
  {
    name: "ansible_show_inventory",
    description: "Show Ansible inventory (hosts and groups)",
    inputSchema: {
      type: "object",
      properties: {
        inventory: {
          type: "string",
          description: "Inventory file to use (default: hosts.yml)",
        },
      },
    },
  },
  {
    name: "ansible_ping",
    description: "Test connectivity to all or specific hosts",
    inputSchema: {
      type: "object",
      properties: {
        hosts: {
          type: "string",
          description: "Host pattern to ping (default: 'all')",
        },
        inventory: {
          type: "string",
          description: "Inventory file to use",
        },
      },
    },
  },
  {
    name: "ansible_dry_run",
    description: "Run a playbook in check mode (dry run)",
    inputSchema: {
      type: "object",
      properties: {
        playbook: {
          type: "string",
          description: "Playbook filename (e.g., 'site.yml')",
        },
        limit: {
          type: "string",
          description: "Limit to specific hosts",
        },
      },
      required: ["playbook"],
    },
  },
  {
    name: "ansible_show_playbook",
    description: "Show the contents of a playbook",
    inputSchema: {
      type: "object",
      properties: {
        playbook: {
          type: "string",
          description: "Playbook filename",
        },
      },
      required: ["playbook"],
    },
  },
  {
    name: "ansible_list_tasks",
    description: "List all tasks in a playbook",
    inputSchema: {
      type: "object",
      properties: {
        playbook: {
          type: "string",
          description: "Playbook filename",
        },
      },
      required: ["playbook"],
    },
  },
];

const server = new Server(
  {
    name: "ansible-mcp-server",
    version: "1.0.0",
  },
  {
    capabilities: {
      tools: {},
    },
  }
);

async function runAnsibleCommand(cmd: string): Promise<string> {
  try {
    const { stdout, stderr } = await execAsync(cmd, {
      cwd: ANSIBLE_DIR,
      env: { ...process.env, ANSIBLE_FORCE_COLOR: "false" },
    });
    return stdout + (stderr ? `\nWarnings:\n${stderr}` : "");
  } catch (error: any) {
    throw new Error(`Ansible command failed: ${error.message}\n${error.stdout || ''}\n${error.stderr || ''}`);
  }
}

server.setRequestHandler(ListToolsRequestSchema, async () => {
  return { tools: TOOLS };
});

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  try {
    switch (name) {
      case "ansible_list_playbooks": {
        const playbooksDir = path.join(ANSIBLE_DIR, "playbooks");
        const files = await fs.readdir(playbooksDir);
        const yamlFiles = files.filter(f => f.endsWith(".yml") || f.endsWith(".yaml"));
        
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify({ playbooks: yamlFiles }, null, 2),
            },
          ],
        };
      }

      case "ansible_list_roles": {
        const rolesDir = path.join(ANSIBLE_DIR, "roles");
        const roles = await fs.readdir(rolesDir);
        
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify({ roles }, null, 2),
            },
          ],
        };
      }

      case "ansible_show_inventory": {
        const inventory = (args?.inventory as string) || "hosts.yml";
        
        const output = await runAnsibleCommand(
          `ansible-inventory -i inventory/${inventory} --list`
        );
        
        return {
          content: [
            {
              type: "text",
              text: output,
            },
          ],
        };
      }

      case "ansible_ping": {
        const hosts = args?.hosts || "all";
        const inventory = args?.inventory || "inventory/hosts.yml";
        
        const output = await runAnsibleCommand(
          `ansible ${hosts} -i ${inventory} -m ping`
        );
        
        return {
          content: [
            {
              type: "text",
              text: output,
            },
          ],
        };
      }

      case "ansible_dry_run": {
        const playbook = args?.playbook as string;
        const limit = args?.limit as string | undefined;
        const limitFlag = limit ? `--limit ${limit}` : "";
        
        const output = await runAnsibleCommand(
          `ansible-playbook playbooks/${playbook} --check ${limitFlag}`
        );
        
        return {
          content: [
            {
              type: "text",
              text: output,
            },
          ],
        };
      }

      case "ansible_show_playbook": {
        const playbook = args?.playbook as string;
        const playbookPath = path.join(ANSIBLE_DIR, "playbooks", playbook);
        const content = await fs.readFile(playbookPath, "utf-8");
        
        return {
          content: [
            {
              type: "text",
              text: content,
            },
          ],
        };
      }

      case "ansible_list_tasks": {
        const playbook = args?.playbook as string;
        
        const output = await runAnsibleCommand(
          `ansible-playbook playbooks/${playbook} --list-tasks`
        );
        
        return {
          content: [
            {
              type: "text",
              text: output,
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
  console.error("Ansible MCP Server running on stdio");
  console.error(`Working directory: ${ANSIBLE_DIR}`);
}

main().catch((error) => {
  console.error("Fatal error:", error);
  process.exit(1);
});
