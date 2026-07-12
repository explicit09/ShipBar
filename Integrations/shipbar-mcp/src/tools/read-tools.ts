import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import {
  ShipbarClient,
  ShipbarCommandError,
  ShipbarUnavailableError,
  type ShipbarEnvelope,
} from "../shipbar-client.js";

// Whitelist schemas: unknown fields (prompt bodies included) are stripped
// before anything reaches the model.
const taskSchema = z
  .object({
    taskID: z.string(),
    title: z.string(),
    taskDescription: z.string().default(""),
    status: z.string(),
    priority: z.string(),
    type: z.string(),
    projectName: z.string().nullish().transform((value) => value ?? null),
    dueDate: z.string().nullish().transform((value) => value ?? null),
    focusDate: z.string().nullish().transform((value) => value ?? null),
    focusOrder: z.number().nullish().transform((value) => value ?? null),
    isInbox: z.boolean(),
    updatedAt: z.string(),
  });

const runSchema = z.object({
  runID: z.string(),
  taskID: z.string(),
  taskTitle: z.string(),
  projectName: z.string().nullish().transform((value) => value ?? null),
  repositoryPath: z.string(),
  status: z.string(),
  updatedAt: z.string(),
});

const tasksResultSchema = z.object({ type: z.literal("tasks"), tasks: z.array(taskSchema) });
const runsResultSchema = z.object({
  type: z.literal("preparedRuns"),
  runs: z.array(runSchema),
});
const runStatusResultSchema = z.object({ type: z.literal("runStatus"), run: runSchema });

type ToolResult = {
  content: Array<{ type: "text"; text: string }>;
  structuredContent?: Record<string, unknown>;
  isError?: boolean;
};

function ok(structured: Record<string, unknown>): ToolResult {
  return {
    content: [{ type: "text", text: JSON.stringify(structured, null, 2) }],
    structuredContent: structured,
  };
}

function toolError(error: unknown): ToolResult {
  const message =
    error instanceof ShipbarUnavailableError || error instanceof ShipbarCommandError
      ? error.message
      : `Unexpected ShipBar bridge failure: ${String(error)}`;
  return { content: [{ type: "text", text: message }], isError: true };
}

function parseTasks(envelope: ShipbarEnvelope): Record<string, unknown> {
  const result = tasksResultSchema.safeParse(envelope.result);
  if (!result.success) {
    throw new ShipbarUnavailableError("ShipBar returned an unexpected task payload.");
  }
  return { tasks: result.data.tasks };
}

export function registerReadTools(server: McpServer, shipbar: ShipbarClient): void {
  const readAnnotations = { readOnlyHint: true, openWorldHint: false } as const;

  server.registerTool(
    "search_tasks",
    {
      title: "Search ShipBar tasks",
      description:
        "Search the user's ShipBar tasks by title and description. Returns compact task summaries.",
      inputSchema: { query: z.string().min(1).describe("Text to match against titles and descriptions") },
      annotations: readAnnotations,
    },
    async ({ query }) => {
      try {
        return ok(parseTasks(await shipbar.call(["search-tasks", "--query", query])));
      } catch (error) {
        return toolError(error);
      }
    },
  );

  server.registerTool(
    "get_today",
    {
      title: "Get today's flight plan",
      description: "List the tasks the user focused for today, in flight-plan order.",
      inputSchema: {},
      annotations: readAnnotations,
    },
    async () => {
      try {
        return ok(parseTasks(await shipbar.call(["get-today"])));
      } catch (error) {
        return toolError(error);
      }
    },
  );

  server.registerTool(
    "get_task",
    {
      title: "Get one ShipBar task",
      description: "Fetch a single ShipBar task with its description by task ID.",
      inputSchema: { taskId: z.string().min(1).describe("The ShipBar task ID") },
      annotations: readAnnotations,
    },
    async ({ taskId }) => {
      try {
        return ok(parseTasks(await shipbar.call(["get-task", "--task", taskId])));
      } catch (error) {
        return toolError(error);
      }
    },
  );

  server.registerTool(
    "list_prepared_runs",
    {
      title: "List prepared agent runs",
      description:
        "List ShipBar agent runs that are prepared for Codex, with task, project, and repository.",
      inputSchema: {},
      annotations: readAnnotations,
    },
    async () => {
      try {
        const envelope = await shipbar.call(["list-prepared"]);
        const result = runsResultSchema.safeParse(envelope.result);
        if (!result.success) {
          throw new ShipbarUnavailableError("ShipBar returned an unexpected run payload.");
        }
        return ok({ runs: result.data.runs });
      } catch (error) {
        return toolError(error);
      }
    },
  );

  server.registerTool(
    "get_run_status",
    {
      title: "Get agent run status",
      description:
        "Fetch the truthful status of one ShipBar agent run (Prepared, Handed off, Running, Needs review, Completed, Failed, or Canceled).",
      inputSchema: { runId: z.string().min(1).describe("The ShipBar run ID") },
      annotations: readAnnotations,
    },
    async ({ runId }) => {
      try {
        const envelope = await shipbar.call(["run-status", "--run", runId]);
        const result = runStatusResultSchema.safeParse(envelope.result);
        if (!result.success) {
          throw new ShipbarUnavailableError("ShipBar returned an unexpected run payload.");
        }
        return ok({ run: result.data.run });
      } catch (error) {
        return toolError(error);
      }
    },
  );
}
