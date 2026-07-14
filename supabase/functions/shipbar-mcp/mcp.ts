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
const readSecurity = [{ type: "oauth2", scopes: ["shipbar.read"] }];
const writeSecurity = [{ type: "oauth2", scopes: ["shipbar.write"] }];

function tool(
  name: string,
  title: string,
  description: string,
  inputSchema: JsonObject,
  readOnly: boolean,
  options: { destructive?: boolean; idempotent?: boolean } = {},
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
      openWorldHint: false,
    },
    _meta: { securitySchemes },
  };
}

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
    "get_today",
    "Get today's ShipBar flight plan",
    "Use this when the user asks what is planned or focused for today. Results are ordered by the current flight plan.",
    { type: "object", additionalProperties: false, properties: {} },
    true,
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
    "Use this when the user asks to add, capture, remember, or schedule work. Include every useful detail the user supplied. Confirm ambiguous title, project, priority, or due date before calling. Success means durably queued, not yet delivered to a device.",
    {
      type: "object",
      additionalProperties: false,
      required: ["idempotencyKey", "title"],
      properties: {
        idempotencyKey: {
          type: "string",
          minLength: 8,
          maxLength: 200,
          description:
            "A stable unique token for this user-approved creation. Reuse it only when retrying the same task.",
        },
        title: { type: "string", minLength: 1, maxLength: 300 },
        description: { type: "string", maxLength: 20000 },
        projectName: { type: "string", maxLength: 200 },
        priority: {
          type: "string",
          enum: ["low", "normal", "high", "urgent"],
          default: "normal",
        },
        dueAt: {
          type: "string",
          format: "date-time",
          description: "An ISO 8601 date-time with timezone.",
        },
      },
    },
    false,
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
  "status",
  "priority",
  "projectName",
  "dueAt",
  "focusDate",
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
  if (name === "get_today") {
    const tasks = await repository.getToday(ownerId);
    return toolResult({ tasks: tasks.map((task) => pick(task, taskFields)) });
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
    const idempotencyKey = text(args.idempotencyKey, "idempotencyKey", 200);
    if (idempotencyKey.length < 8) {
      throw new Error("idempotencyKey is too short.");
    }
    const capture = await repository.enqueueCapture(
      ownerId,
      idempotencyKey,
      parseCapture(args),
    );
    const safe = pick(capture, [
      "id",
      "status",
      "title",
      "projectName",
      "priority",
      "dueAt",
    ]);
    return toolResult(
      { capture: safe },
      `ShipBar durably queued “${String(safe.title ?? args.title)}”. Status: ${
        String(safe.status ?? "queued")
      }.`,
    );
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
      scopes_supported: ["shipbar.read", "shipbar.write"],
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
      serverInfo: { name: "ShipBar", version: "0.2.0" },
      instructions:
        "ShipBar is the owner's private task and execution queue. Read before changing. A create or execution response marked queued proves durable acceptance only; never claim delivered, running, or completed until a later status says so. Before queue_execution, list devices and obtain explicit approval for the exact task and device.",
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
