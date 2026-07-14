import {
  isDeviceOnline,
  parseCapture,
  parseExecution,
} from "../shipbar-relay/domain.ts";
import type { RelayRepository } from "../shipbar-relay/router.ts";

type JsonObject = Record<string, unknown>;
type JsonRpcId = string | number | null;

export type McpDependencies = {
  ownerId: string;
  resourceUrl: string;
  authorizationServer: string;
  repository: RelayRepository;
  authorize: (token: string) => Promise<boolean>;
  now?: () => Date;
};

const protocolVersion = "2025-06-18";
const iconUrl =
  "https://uyutoheyrvodwcpufkda.supabase.co/functions/v1/shipbar-mcp/icon.svg";
const iconSvg = `
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" role="img" aria-label="ShipBar">
  <rect width="512" height="512" rx="112" fill="#181a19"/>
  <path d="M92 333 414 118 303 405l-45-106-92 81 18-118z" fill="#f5f3ed"/>
  <path d="m184 262 146-74-72 111z" fill="#181a19"/>
  <path d="M307 103a73 73 0 0 1 83 50M298 65a113 113 0 0 1 131 78" fill="none" stroke="#9a8bea" stroke-width="20" stroke-linecap="round"/>
</svg>`.trim();
// Supabase's OAuth server currently advertises its identity scopes. Authorization
// is still least-privilege here because every token must belong to the one
// configured owner and write tools remain confirmation-gated by ChatGPT.
const readSecurity = [{ type: "oauth2", scopes: ["email"] }];
const writeSecurity = [{ type: "oauth2", scopes: ["email"] }];

function tool(
  name: string,
  title: string,
  description: string,
  inputSchema: JsonObject,
  readOnly: boolean,
  options: { destructive?: boolean; idempotent?: boolean; openWorld?: boolean } = {},
): JsonObject {
  const securitySchemes = readOnly ? readSecurity : writeSecurity;
  return {
    name,
    title,
    description,
    inputSchema,
    securitySchemes,
    annotations: {
      readOnlyHint: readOnly,
      destructiveHint: options.destructive ?? false,
      idempotentHint: options.idempotent ?? readOnly,
      openWorldHint: options.openWorld ?? false,
    },
    _meta: { securitySchemes },
  };
}

const idempotencyProperty = {
  type: "string", minLength: 8, maxLength: 200,
  description: "A stable unique token for this exact mutation. Reuse it only to retry the same approved request.",
};
const deviceProperty = {
  type: "string", maxLength: 200,
  description: "Optional registered ShipBar device. Omit to use the most recently seen productivity-capable device.",
};
const taskPatchProperties = {
  title: { type: "string", minLength: 1, maxLength: 300 },
  description: { type: "string", maxLength: 20000, description: "Human-readable context, details, and acceptance criteria." },
  prompt: { type: "string", maxLength: 20000, description: "Instructions an execution agent should follow; do not duplicate ordinary context here." },
  status: { type: "string", enum: ["todo", "doing", "done"] },
  priority: { type: "string", enum: ["low", "medium", "high"] },
  type: { type: "string", enum: ["feature", "bug", "chore", "idea"] },
  projectId: { type: "string", maxLength: 200 },
  projectName: { type: "string", maxLength: 200 },
  dueAt: { type: "string", format: "date-time", description: "ISO 8601 with timezone." },
  focusDate: { type: "string", format: "date", description: "YYYY-MM-DD date to place the task on Today." },
  focusOrder: { type: "integer", minimum: 0 },
  sourceApp: { type: "string", maxLength: 200 },
  sourceUrl: { type: "string", maxLength: 4000 },
  clearProject: { type: "boolean" },
  clearDueDate: { type: "boolean" },
  removeFromToday: { type: "boolean" },
};
const projectPatchProperties = {
  name: { type: "string", minLength: 1, maxLength: 200 },
  outcome: { type: "string", maxLength: 20000, description: "The successful end state for this project." },
  basePrompt: { type: "string", maxLength: 20000, description: "Reusable instructions inherited by work in this project." },
  repoPath: { type: "string", maxLength: 2000, description: "Optional local repository path; required before Codex execution." },
  color: { type: "string", maxLength: 100 },
  icon: { type: "string", maxLength: 200 },
  sortOrder: { type: "integer", minimum: 0 },
};

const tools = [
  tool(
    "search_tasks",
    "Search ShipBar tasks",
    "Use this when the user wants to find existing ShipBar work by words in its title or description. Do not use it to create or modify tasks.",
    {
      type: "object",
      additionalProperties: false,
      required: ["query"],
      properties: {
        query: {
          type: "string",
          minLength: 1,
          maxLength: 300,
          description: "Words to match in task titles and descriptions.",
        },
      },
    },
    true,
  ),
  tool(
    "list_tasks", "List ShipBar tasks",
    "Use this to browse tasks by status, priority, type, project, Inbox, or Trash. Read current records before updating them.",
    { type: "object", additionalProperties: false, properties: {
      status: { type: "string", enum: ["todo", "doing", "done"] },
      priority: { type: "string", enum: ["low", "medium", "high"] },
      type: { type: "string", enum: ["feature", "bug", "chore", "idea"] },
      projectName: { type: "string", maxLength: 200 }, inbox: { type: "boolean" },
      trashed: { type: "boolean", default: false },
    } }, true,
  ),
  tool(
    "get_task", "Get a ShipBar task",
    "Read the complete current task, including its revision, before editing, moving, trashing, restoring, or deleting it.",
    { type: "object", additionalProperties: false, required: ["taskId"], properties: { taskId: { type: "string", minLength: 1, maxLength: 200 } } }, true,
  ),
  tool(
    "get_today",
    "Get today's ShipBar flight plan",
    "Use this when the user asks what is planned or focused for today. Results are ordered by the current flight plan.",
    { type: "object", additionalProperties: false, properties: {} },
    true,
  ),
  tool(
    "list_projects", "List ShipBar projects",
    "List active project workspaces and their current revisions. Set includeTrashed only when reviewing Trash.",
    { type: "object", additionalProperties: false, properties: { includeTrashed: { type: "boolean", default: false } } }, true,
  ),
  tool(
    "get_project", "Get a ShipBar project",
    "Read the complete current project, including outcome, reusable base prompt, repository, and revision, before changing it.",
    { type: "object", additionalProperties: false, required: ["projectId"], properties: { projectId: { type: "string", minLength: 1, maxLength: 200 } } }, true,
  ),
  tool(
    "list_trash", "List ShipBar Trash",
    "Show recoverable trashed tasks and projects. Nothing here is permanently deleted until the user explicitly requests it.",
    { type: "object", additionalProperties: false, properties: {} }, true,
  ),
  tool(
    "list_devices",
    "List ShipBar devices",
    "Use this before queue_execution to show the user which ShipBar devices are registered and which are currently online. Never invent online status.",
    { type: "object", additionalProperties: false, properties: {} },
    true,
  ),
  tool(
    "create_task",
    "Create a ShipBar task",
    "Use when the user asks to add, capture, remember, or schedule work. Preserve every supplied detail: description is human context; prompt is agent instruction. Clarify only materially ambiguous project or date information. A queued command is not yet applied.",
    {
      type: "object",
      additionalProperties: false,
      required: ["idempotencyKey", "title"],
      properties: {
        idempotencyKey: idempotencyProperty, deviceId: deviceProperty,
        ...taskPatchProperties,
      },
    },
    false,
  ),
  tool(
    "update_task", "Update a ShipBar task",
    "Use after get_task. Change only fields the user requested; unspecified fields are preserved. This also moves projects, manages Today, and marks doing, done, or reopened.",
    { type: "object", additionalProperties: false, required: ["idempotencyKey", "taskId", "expectedRevision"], properties: {
      idempotencyKey: idempotencyProperty, deviceId: deviceProperty,
      taskId: { type: "string", minLength: 1, maxLength: 200 },
      expectedRevision: { type: "integer", minimum: 0 }, ...taskPatchProperties,
    } }, false,
  ),
  tool(
    "create_project", "Create a ShipBar project",
    "Create a project workspace. Outcome defines success; basePrompt contains reusable instructions; repoPath is optional until Codex work is queued.",
    { type: "object", additionalProperties: false, required: ["idempotencyKey", "name"], properties: {
      idempotencyKey: idempotencyProperty, deviceId: deviceProperty, ...projectPatchProperties,
    } }, false,
  ),
  tool(
    "update_project", "Update a ShipBar project",
    "Use after get_project. Change only requested fields and preserve all unspecified project context.",
    { type: "object", additionalProperties: false, required: ["idempotencyKey", "projectId", "expectedRevision"], properties: {
      idempotencyKey: idempotencyProperty, deviceId: deviceProperty,
      projectId: { type: "string", minLength: 1, maxLength: 200 },
      expectedRevision: { type: "integer", minimum: 0 }, ...projectPatchProperties,
    } }, false,
  ),
  tool(
    "trash_record", "Move a ShipBar record to Trash",
    "Requires explicit user confirmation. For projects, taskHandling must say whether contained tasks move to Inbox or enter Trash too. This remains recoverable.",
    { type: "object", additionalProperties: false, required: ["idempotencyKey", "recordType", "recordId", "expectedRevision"], properties: {
      idempotencyKey: idempotencyProperty, deviceId: deviceProperty,
      recordType: { type: "string", enum: ["task", "project"] }, recordId: { type: "string", minLength: 1, maxLength: 200 },
      expectedRevision: { type: "integer", minimum: 0 }, taskHandling: { type: "string", enum: ["move_tasks_to_inbox", "trash_tasks"] },
    } }, false, { destructive: true },
  ),
  tool(
    "restore_record", "Restore a ShipBar record",
    "Restore a task or project from recoverable Trash after reading its current trashed revision.",
    { type: "object", additionalProperties: false, required: ["idempotencyKey", "recordType", "recordId", "expectedRevision"], properties: {
      idempotencyKey: idempotencyProperty, deviceId: deviceProperty,
      recordType: { type: "string", enum: ["task", "project"] }, recordId: { type: "string", minLength: 1, maxLength: 200 },
      expectedRevision: { type: "integer", minimum: 0 },
    } }, false,
  ),
  tool(
    "permanently_delete_record", "Permanently delete a ShipBar record",
    "Requires explicit user confirmation and works only on an already-trashed task or project. This cannot be undone.",
    { type: "object", additionalProperties: false, required: ["idempotencyKey", "recordType", "recordId", "expectedRevision"], properties: {
      idempotencyKey: idempotencyProperty, deviceId: deviceProperty,
      recordType: { type: "string", enum: ["task", "project"] }, recordId: { type: "string", minLength: 1, maxLength: 200 },
      expectedRevision: { type: "integer", minimum: 0 },
    } }, false, { destructive: true },
  ),
  tool(
    "get_command_status", "Get ShipBar command status",
    "Use after any mutation. Report queued, claimed, applied, failed, conflicted, or canceled exactly; never call queued or claimed complete.",
    { type: "object", additionalProperties: false, required: ["commandId"], properties: { commandId: { type: "string", minLength: 1, maxLength: 200 } } }, true,
  ),
  tool(
    "queue_execution",
    "Queue a Codex execution",
    "Use this only after list_devices and explicit user approval of the exact task, device, repository, and instructions. Success means queued; call get_execution_status before claiming it is running or complete.",
    {
      type: "object",
      additionalProperties: false,
      required: ["idempotencyKey", "taskId", "deviceId"],
      properties: {
        idempotencyKey: {
          type: "string",
          minLength: 8,
          maxLength: 200,
          description:
            "A stable unique token for this approved execution. Reuse it only when retrying the same request.",
        },
        taskId: { type: "string", minLength: 1, maxLength: 200 },
        deviceId: { type: "string", minLength: 1, maxLength: 200 },
        repositoryPath: { type: "string", maxLength: 2000 },
        instructions: { type: "string", maxLength: 20000 },
      },
    },
    false,
    { destructive: true, openWorld: true },
  ),
  tool(
    "get_execution_status",
    "Get ShipBar execution status",
    "Use this after queue_execution to report the latest truthful lifecycle state: queued, claimed, running, needs_review, completed, failed, or canceled.",
    {
      type: "object",
      additionalProperties: false,
      required: ["executionId"],
      properties: {
        executionId: { type: "string", minLength: 1, maxLength: 200 },
      },
    },
    true,
  ),
];

function headers(extra: HeadersInit = {}): Headers {
  const result = new Headers(extra);
  result.set("Cache-Control", "no-store");
  result.set("X-Content-Type-Options", "nosniff");
  result.set("Access-Control-Allow-Origin", "*");
  result.set(
    "Access-Control-Allow-Headers",
    "Authorization, Content-Type, MCP-Protocol-Version",
  );
  result.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  return result;
}

function json(body: unknown, status = 200): Response {
  return Response.json(body, { status, headers: headers() });
}

function result(id: JsonRpcId, value: unknown): Response {
  return json({ jsonrpc: "2.0", id, result: value });
}

function rpcError(
  id: JsonRpcId,
  code: number,
  message: string,
  status = 200,
): Response {
  return json({ jsonrpc: "2.0", id, error: { code, message } }, status);
}

function object(value: unknown, name: string): JsonObject {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`${name} must be an object.`);
  }
  return value as JsonObject;
}

function text(value: unknown, name: string, maxLength: number): string {
  if (typeof value !== "string" || !value.trim()) {
    throw new Error(`${name} is required.`);
  }
  const cleaned = value.trim();
  if (cleaned.length > maxLength) throw new Error(`${name} is too long.`);
  return cleaned;
}

function bearer(request: Request): string {
  const authorization = request.headers.get("Authorization") ?? "";
  return authorization.match(/^Bearer\s+(.+)$/i)?.[1]?.trim() ?? "";
}

function authChallenge(dependencies: McpDependencies): JsonObject {
  const metadataUrl =
    `${dependencies.resourceUrl}/.well-known/oauth-protected-resource`;
  return {
    content: [{
      type: "text",
      text:
        "Connect your private ShipBar account to use this tool. No ShipBar data was read or changed.",
    }],
    isError: true,
    _meta: {
      "mcp/www_authenticate": [
        `Bearer resource_metadata="${metadataUrl}", error="invalid_token", error_description="ShipBar authorization is required"`,
      ],
    },
  };
}

const taskFields = [
  "taskId",
  "title",
  "description",
  "prompt",
  "status",
  "priority",
  "type",
  "projectName",
  "dueAt",
  "focusDate",
  "focusOrder",
  "isInbox",
  "sourceApp",
  "sourceUrl",
  "revision",
  "trashedAt",
  "sourceUpdatedAt",
] as const;
const projectFields = [
  "projectId", "name", "outcome", "basePrompt", "repoPath", "color", "icon",
  "sortOrder", "revision", "trashedAt", "sourceUpdatedAt",
] as const;
const commandFields = [
  "id", "deviceId", "kind", "status", "summary", "result", "createdAt",
  "updatedAt", "appliedAt",
] as const;
const deviceFields = [
  "deviceId",
  "name",
  "platform",
  "capabilities",
  "lastSeenAt",
] as const;
const executionFields = [
  "id",
  "taskId",
  "deviceId",
  "status",
  "localRunId",
  "resultSummary",
  "repositoryPath",
  "instructions",
] as const;

function pick(value: JsonObject, fields: readonly string[]): JsonObject {
  return Object.fromEntries(
    fields.filter((field) => value[field] !== undefined).map((
      field,
    ) => [field, value[field]]),
  );
}

function toolResult(
  structuredContent: JsonObject,
  message?: string,
): JsonObject {
  return {
    content: [{
      type: "text",
      text: message ?? JSON.stringify(structuredContent, null, 2),
    }],
    structuredContent,
  };
}

function optionalString(value: unknown, maxLength: number): string | undefined {
  if (value === undefined) return undefined;
  if (typeof value !== "string") throw new Error("Expected text.");
  if (value.length > maxLength) throw new Error("Text is too long.");
  return value;
}

function taskPatch(args: JsonObject): JsonObject {
  const patch: JsonObject = {};
  const direct = [
    "title", "description", "prompt", "status", "priority", "type", "projectName",
    "dueAt", "focusDate", "focusOrder", "sourceApp", "clearProject", "clearDueDate",
    "removeFromToday",
  ];
  for (const key of direct) if (args[key] !== undefined) patch[key] = args[key];
  if (args.projectId !== undefined) patch.projectID = args.projectId;
  if (args.sourceUrl !== undefined) patch.sourceURL = args.sourceUrl;
  return patch;
}

function projectPatch(args: JsonObject): JsonObject {
  const patch: JsonObject = {};
  for (const key of ["name", "outcome", "basePrompt", "repoPath", "color", "icon", "sortOrder"]) {
    if (args[key] !== undefined) patch[key] = args[key];
  }
  return patch;
}

async function commandDeviceId(args: JsonObject, dependencies: McpDependencies): Promise<string> {
  const devices = await dependencies.repository.listDevices(dependencies.ownerId);
  const requested = optionalString(args.deviceId, 200)?.trim();
  if (requested) {
    if (!devices.some((device) => String(device.deviceId) === requested)) {
      throw new Error("The requested ShipBar device is not registered.");
    }
    return requested;
  }
  const eligible = devices.find((device) =>
    Array.isArray(device.capabilities) && device.capabilities.includes("productivity-commands")
  ) ?? devices.find((device) => String(device.platform) === "macos") ?? devices[0];
  if (!eligible) throw new Error("No ShipBar device is registered to receive this command.");
  return text(eligible.deviceId, "deviceId", 200);
}

async function enqueueProductivity(
  kind: string,
  payload: JsonObject,
  args: JsonObject,
  dependencies: McpDependencies,
): Promise<JsonObject> {
  const idempotencyKey = text(args.idempotencyKey, "idempotencyKey", 200);
  if (idempotencyKey.length < 8) throw new Error("idempotencyKey is too short.");
  const command = await dependencies.repository.enqueueCommand(
    dependencies.ownerId,
    idempotencyKey,
    { deviceId: await commandDeviceId(args, dependencies), kind, payload },
  );
  const safe = pick(command, commandFields);
  return toolResult(
    { command: safe },
    `ShipBar durably queued ${kind} command ${String(safe.id ?? "")}. Status: ${String(safe.status ?? "queued")}. Call get_command_status before claiming the change was applied.`,
  );
}

async function callTool(
  name: string,
  args: JsonObject,
  dependencies: McpDependencies,
): Promise<JsonObject> {
  const repository = dependencies.repository;
  const ownerId = dependencies.ownerId;
  if (name === "search_tasks") {
    const tasks = await repository.searchTasks(
      ownerId,
      text(args.query, "query", 300),
    );
    return toolResult({ tasks: tasks.map((task) => pick(task, taskFields)) });
  }
  if (name === "list_tasks") {
    const tasks = await repository.listTasks(ownerId, args);
    return toolResult({ tasks: tasks.map((task) => pick(task, taskFields)) });
  }
  if (name === "get_task") {
    const task = await repository.getTask(ownerId, text(args.taskId, "taskId", 200));
    if (!task) throw new Error("Task was not found.");
    return toolResult({ task: pick(task, taskFields) });
  }
  if (name === "get_today") {
    const tasks = await repository.getToday(ownerId);
    return toolResult({ tasks: tasks.map((task) => pick(task, taskFields)) });
  }
  if (name === "list_projects") {
    const projects = await repository.listProjects(ownerId, args.includeTrashed === true);
    return toolResult({ projects: projects.map((project) => pick(project, projectFields)) });
  }
  if (name === "get_project") {
    const project = await repository.getProject(ownerId, text(args.projectId, "projectId", 200));
    if (!project) throw new Error("Project was not found.");
    return toolResult({ project: pick(project, projectFields) });
  }
  if (name === "list_trash") {
    const [tasks, projects] = await Promise.all([
      repository.listTasks(ownerId, { trashed: true }),
      repository.listProjects(ownerId, true),
    ]);
    return toolResult({
      tasks: tasks.filter((task) => task.trashedAt).map((task) => pick(task, taskFields)),
      projects: projects.filter((project) => project.trashedAt).map((project) => pick(project, projectFields)),
    });
  }
  if (name === "list_devices") {
    const now = (dependencies.now ?? (() => new Date()))();
    const devices = (await repository.listDevices(ownerId)).map((device) => ({
      ...pick(device, deviceFields),
      online: isDeviceOnline(
        String(device.lastSeenAt ?? device.last_seen_at ?? ""),
        now,
      ),
    }));
    return toolResult({ devices });
  }
  if (name === "create_task") {
    text(args.title, "title", 300);
    return await enqueueProductivity("createTask", { kind: "createTask", task: taskPatch(args) }, args, dependencies);
  }
  if (name === "update_task") {
    return await enqueueProductivity("updateTask", {
      kind: "updateTask", recordID: text(args.taskId, "taskId", 200),
      expectedRevision: args.expectedRevision, task: taskPatch(args),
    }, args, dependencies);
  }
  if (name === "create_project") {
    text(args.name, "name", 200);
    return await enqueueProductivity("createProject", { kind: "createProject", project: projectPatch(args) }, args, dependencies);
  }
  if (name === "update_project") {
    return await enqueueProductivity("updateProject", {
      kind: "updateProject", recordID: text(args.projectId, "projectId", 200),
      expectedRevision: args.expectedRevision, project: projectPatch(args),
    }, args, dependencies);
  }
  if (name === "trash_record" || name === "restore_record" || name === "permanently_delete_record") {
    const type = text(args.recordType, "recordType", 20);
    const prefix = name === "trash_record" ? "trash" : name === "restore_record" ? "restore" : "permanentlyDelete";
    const kind = `${prefix}${type === "task" ? "Task" : "Project"}`;
    return await enqueueProductivity(kind, {
      kind, recordID: text(args.recordId, "recordId", 200),
      expectedRevision: args.expectedRevision,
      ...(args.taskHandling !== undefined ? { taskHandling: args.taskHandling } : {}),
    }, args, dependencies);
  }
  if (name === "get_command_status") {
    const command = await repository.getCommand(ownerId, text(args.commandId, "commandId", 200));
    if (!command) throw new Error("Command was not found.");
    return toolResult({ command: pick(command, commandFields) });
  }
  if (name === "queue_execution") {
    const idempotencyKey = text(args.idempotencyKey, "idempotencyKey", 200);
    if (idempotencyKey.length < 8) {
      throw new Error("idempotencyKey is too short.");
    }
    const execution = await repository.enqueueExecution(
      ownerId,
      idempotencyKey,
      parseExecution(args),
    );
    const safe = pick(execution, executionFields);
    return toolResult(
      { execution: safe },
      `ShipBar queued execution ${String(safe.id ?? "")}. Status: ${
        String(safe.status ?? "queued")
      }.`,
    );
  }
  if (name === "get_execution_status") {
    const execution = await repository.getExecution(
      ownerId,
      text(args.executionId, "executionId", 200),
    );
    if (!execution) throw new Error("Execution was not found.");
    return toolResult({ execution: pick(execution, executionFields) });
  }
  throw new Error(`Unknown tool: ${name}`);
}

export async function handleMcpRequest(
  request: Request,
  dependencies: McpDependencies,
): Promise<Response> {
  const path = new URL(request.url).pathname;
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: headers() });
  }
  if (
    request.method === "GET" &&
    path.endsWith("/.well-known/oauth-protected-resource")
  ) {
    return json({
      resource: dependencies.resourceUrl,
      authorization_servers: [dependencies.authorizationServer],
      scopes_supported: ["email"],
    });
  }
  if (request.method === "GET" && path.endsWith("/icon.svg")) {
    return new Response(iconSvg, {
      status: 200,
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Cache-Control": "public, max-age=86400",
        "Content-Disposition": "inline",
        "Content-Type": "image/svg+xml; charset=utf-8",
      },
    });
  }
  if (request.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  let message: JsonObject;
  try {
    message = object(await request.json(), "JSON-RPC request");
  } catch {
    return rpcError(null, -32700, "Parse error", 400);
  }
  const id =
    (typeof message.id === "string" || typeof message.id === "number" ||
        message.id === null)
      ? message.id as JsonRpcId
      : null;
  const method = typeof message.method === "string" ? message.method : "";
  if (message.jsonrpc !== "2.0" || !method) {
    return rpcError(id, -32600, "Invalid Request", 400);
  }

  if (!Object.hasOwn(message, "id")) {
    return new Response(null, { status: 202, headers: headers() });
  }
  if (method === "initialize") {
    return result(id, {
      protocolVersion,
      capabilities: { tools: { listChanged: false } },
      serverInfo: {
        name: "ShipBar",
        version: "0.3.0",
        icons: [{ src: iconUrl, mimeType: "image/svg+xml", sizes: ["512x512"] }],
      },
      instructions:
        "ShipBar is the owner's private local-first productivity system. Read a task or project and its revision before changing it. Preserve supplied detail: descriptions are human context, prompts/base prompts are agent instructions, and project outcomes define success. Ordinary create, edit, move, Today, and completion changes may proceed directly. Trash, permanent delete, and Codex execution require explicit approval. Every mutation is queued first; call get_command_status and never claim it happened until status is applied. Conflicted means reread before retrying. Before queue_execution, list devices and obtain approval for the exact task, device, repository, and instructions.",
    });
  }
  if (method === "ping") return result(id, {});
  if (method === "tools/list") return result(id, { tools });
  if (method !== "tools/call") return rpcError(id, -32601, "Method not found");

  const params = object(message.params ?? {}, "params");
  const name = text(params.name, "tool name", 200);
  const args = object(params.arguments ?? {}, "arguments");
  if (!await dependencies.authorize(bearer(request))) {
    return result(id, authChallenge(dependencies));
  }
  try {
    return result(id, await callTool(name, args, dependencies));
  } catch (cause) {
    const errorMessage = cause instanceof Error
      ? cause.message
      : "ShipBar could not complete this tool call.";
    return result(id, {
      content: [{ type: "text", text: errorMessage }],
      isError: true,
    });
  }
}
