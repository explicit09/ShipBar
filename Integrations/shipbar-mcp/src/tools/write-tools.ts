import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import type { ShipbarCapabilities } from "../capabilities.js";
import type { ShipbarClient } from "../shipbar-client.js";

/**
 * Write adapters stay unregistered unless the connected surface supports
 * writes AND the operator opted in. When a supported surface exists, these
 * adapters must route through ShipBar's durable capture queue and run
 * lifecycle (via the signed helper) — never by mutating storage directly.
 */
export function registerWriteTools(
  server: McpServer,
  _shipbar: ShipbarClient,
  capabilities: ShipbarCapabilities,
): void {
  if (!capabilities.writesEnabled) {
    return;
  }

  const capabilityError = () => ({
    content: [
      {
        type: "text" as const,
        text:
          "ShipBar write capability is not supported on this ChatGPT surface yet. " +
          "No change was made. Capture the task on your phone or Mac instead.",
      },
    ],
    isError: true,
  });

  server.registerTool(
    "create_task",
    {
      title: "Create a ShipBar task",
      description:
        "Queue a new ShipBar task through the durable capture queue. Confirm the title with the user before calling.",
      inputSchema: {
        title: z.string().min(1),
        description: z.string().optional(),
        project: z.string().optional(),
      },
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false },
    },
    async () => capabilityError(),
  );

  server.registerTool(
    "update_task",
    {
      title: "Update a ShipBar task",
      description:
        "Update an existing ShipBar task. Confirm the exact task and change with the user before calling.",
      inputSchema: { taskId: z.string().min(1), title: z.string().optional() },
      annotations: { readOnlyHint: false, destructiveHint: true, idempotentHint: false },
    },
    async () => capabilityError(),
  );

  server.registerTool(
    "complete_task",
    {
      title: "Complete a ShipBar task",
      description:
        "Mark a ShipBar task done. Confirm the exact task with the user before calling; this changes their plan.",
      inputSchema: { taskId: z.string().min(1) },
      annotations: { readOnlyHint: false, destructiveHint: true, idempotentHint: true },
    },
    async () => capabilityError(),
  );

  server.registerTool(
    "prepare_run",
    {
      title: "Prepare a Codex run",
      description:
        "Prepare a ShipBar task for a Codex run through the run lifecycle. Confirm the task and repository with the user before calling.",
      inputSchema: { taskId: z.string().min(1) },
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false },
    },
    async () => capabilityError(),
  );
}
