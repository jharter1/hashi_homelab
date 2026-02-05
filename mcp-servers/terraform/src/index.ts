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

const execAsync = promisify(exec);

// Default to the terraform directory in the homelab repo
const TERRAFORM_DIR = process.env.TERRAFORM_DIR || "/Users/jackharter/Developer/hashi_homelab/terraform";

const TOOLS: Tool[] = [
  {
    name: "terraform_validate",
    description: "Validate Terraform configuration files",
    inputSchema: {
      type: "object",
      properties: {
        environment: {
          type: "string",
          description: "Environment to validate (e.g., 'dev', 'hub')",
        },
      },
    },
  },
  {
    name: "terraform_plan",
    description: "Run terraform plan to see what changes would be made",
    inputSchema: {
      type: "object",
      properties: {
        environment: {
          type: "string",
          description: "Environment to plan (e.g., 'dev', 'hub')",
          required: true,
        },
      },
      required: ["environment"],
    },
  },
  {
    name: "terraform_show_state",
    description: "Show current Terraform state",
    inputSchema: {
      type: "object",
      properties: {
        environment: {
          type: "string",
          description: "Environment to show state for",
        },
      },
    },
  },
  {
    name: "terraform_list_resources",
    description: "List all resources in Terraform state",
    inputSchema: {
      type: "object",
      properties: {
        environment: {
          type: "string",
          description: "Environment to list resources for",
        },
      },
    },
  },
  {
    name: "terraform_output",
    description: "Get Terraform outputs",
    inputSchema: {
      type: "object",
      properties: {
        environment: {
          type: "string",
          description: "Environment to get outputs from",
        },
        output_name: {
          type: "string",
          description: "Specific output name (optional)",
        },
      },
    },
  },
  {
    name: "terraform_fmt_check",
    description: "Check if Terraform files are properly formatted",
    inputSchema: {
      type: "object",
      properties: {
        path: {
          type: "string",
          description: "Path to check (relative to terraform dir)",
        },
      },
    },
  },
];

const server = new Server(
  {
    name: "terraform-mcp-server",
    version: "1.0.0",
  },
  {
    capabilities: {
      tools: {},
    },
  }
);

async function runTerraformCommand(cmd: string, env?: string): Promise<string> {
  const workDir = env 
    ? path.join(TERRAFORM_DIR, "environments", env)
    : TERRAFORM_DIR;
  
  try {
    const { stdout, stderr } = await execAsync(cmd, {
      cwd: workDir,
      env: { ...process.env },
    });
    return stdout + (stderr ? `\nWarnings:\n${stderr}` : "");
  } catch (error: any) {
    throw new Error(`Terraform command failed: ${error.message}\n${error.stdout || ''}\n${error.stderr || ''}`);
  }
}

server.setRequestHandler(ListToolsRequestSchema, async () => {
  return { tools: TOOLS };
});

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  try {
    switch (name) {
      case "terraform_validate": {
        const env = args?.environment as string | undefined;
        const output = await runTerraformCommand("terraform validate -json", env);
        
        return {
          content: [
            {
              type: "text",
              text: output,
            },
          ],
        };
      }

      case "terraform_plan": {
        const env = args?.environment as string;
        const output = await runTerraformCommand("terraform plan -no-color", env);
        
        return {
          content: [
            {
              type: "text",
              text: output,
            },
          ],
        };
      }

      case "terraform_show_state": {
        const env = args?.environment as string | undefined;
        const output = await runTerraformCommand("terraform show -no-color", env);
        
        return {
          content: [
            {
              type: "text",
              text: output,
            },
          ],
        };
      }

      case "terraform_list_resources": {
        const env = args?.environment as string | undefined;
        const output = await runTerraformCommand("terraform state list", env);
        
        return {
          content: [
            {
              type: "text",
              text: output,
            },
          ],
        };
      }

      case "terraform_output": {
        const env = args?.environment as string | undefined;
        const outputName = args?.output_name as string | undefined;
        const cmd = outputName 
          ? `terraform output -json ${outputName}`
          : "terraform output -json";
        
        const output = await runTerraformCommand(cmd, env);
        
        return {
          content: [
            {
              type: "text",
              text: output,
            },
          ],
        };
      }

      case "terraform_fmt_check": {
        const checkPath = args?.path as string | undefined;
        const targetPath = checkPath 
          ? path.join(TERRAFORM_DIR, checkPath)
          : TERRAFORM_DIR;
        
        const { stdout } = await execAsync(`terraform fmt -check -recursive ${targetPath}`);
        
        return {
          content: [
            {
              type: "text",
              text: stdout || "All files are properly formatted",
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
  console.error("Terraform MCP Server running on stdio");
  console.error(`Working directory: ${TERRAFORM_DIR}`);
}

main().catch((error) => {
  console.error("Fatal error:", error);
  process.exit(1);
});
