#!/usr/bin/env node
import { pathToFileURL } from "node:url";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { resolveCapabilities } from "./capabilities.js";
import { ShipbarClient } from "./shipbar-client.js";
import { registerReadTools } from "./tools/read-tools.js";
import { registerWriteTools } from "./tools/write-tools.js";

export function createShipbarServer(options: {
  shipbar: ShipbarClient;
  surface: string;
  env: Record<string, string | undefined>;
}): McpServer {
  const capabilities = resolveCapabilities(options.surface, options.env);
  const server = new McpServer({
    name: "shipbar",
    version: "0.1.0",
  });
  registerReadTools(server, options.shipbar);
  registerWriteTools(server, options.shipbar, capabilities);
  return server;
}

async function main(): Promise<void> {
  const server = createShipbarServer({
    shipbar: new ShipbarClient({ binaryPath: process.env.SHIPBARCTL_PATH }),
    surface: process.env.SHIPBAR_SURFACE ?? "personal-pro",
    env: process.env,
  });
  await server.connect(new StdioServerTransport());
  console.error("shipbar-mcp: ready (stdio)");
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.error(`shipbar-mcp: fatal ${String(error)}`);
    process.exit(1);
  });
}
