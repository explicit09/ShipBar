import { isAuthorized, isDeviceOnline, parseCapture, parseExecution } from "./domain.ts";
import { RelayConflictError, RelayStateConflictError, RelayStorageError } from "./repository.ts";

type JsonObject = Record<string, unknown>;

export interface RelayRepository {
  searchTasks(ownerId: string, query: string): Promise<JsonObject[]>;
  listTasks(ownerId: string, filters: JsonObject): Promise<JsonObject[]>;
  getTask(ownerId: string, taskId: string): Promise<JsonObject | null>;
  getToday(ownerId: string): Promise<JsonObject[]>;
  listProjects(ownerId: string, includeTrashed: boolean): Promise<JsonObject[]>;
  getProject(ownerId: string, projectId: string): Promise<JsonObject | null>;
  enqueueCapture(ownerId: string, idempotencyKey: string, input: JsonObject): Promise<JsonObject>;
  listDevices(ownerId: string): Promise<JsonObject[]>;
  enqueueExecution(ownerId: string, idempotencyKey: string, input: JsonObject): Promise<JsonObject>;
  getExecution(ownerId: string, executionId: string): Promise<JsonObject | null>;
  enqueueCommand(ownerId: string, idempotencyKey: string, input: JsonObject): Promise<JsonObject>;
  getCommand(ownerId: string, commandId: string): Promise<JsonObject | null>;
  pull(ownerId: string, deviceId: string): Promise<JsonObject>;
  push(ownerId: string, payload: JsonObject): Promise<JsonObject>;
}

export type RelayDependencies = {
  ownerId: string;
  keyHash: string;
  repository: RelayRepository;
  now?: () => Date;
};

function json(body: unknown, status = 200): Response {
  return Response.json(body, {
    status,
    headers: { "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff" },
  });
}

function error(status: number, code: string, message: string): Response {
  return json({ error: code, message }, status);
}

async function body(request: Request): Promise<JsonObject> {
  const value = await request.json();
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Request body must be a JSON object.");
  }
  return value as JsonObject;
}

function requiredText(value: unknown, name: string): string {
  if (typeof value !== "string" || value.trim() === "") throw new Error(`${name} is required.`);
  return value.trim();
}

function idempotencyKey(request: Request): string {
  const value = request.headers.get("Idempotency-Key")?.trim();
  if (!value || value.length < 8 || value.length > 200) {
    throw new Error("Idempotency-Key header must contain 8 to 200 characters.");
  }
  return value;
}

function routePath(request: Request): string {
  const path = new URL(request.url).pathname;
  const marker = "/shipbar-relay";
  const index = path.indexOf(marker);
  return index >= 0 ? path.slice(index + marker.length) || "/" : path;
}

export async function handleRelayRequest(
  request: Request,
  dependencies: RelayDependencies,
): Promise<Response> {
  if (!await isAuthorized(request.headers.get("X-ShipBar-Key"), dependencies.keyHash)) {
    return error(401, "unauthorized", "A valid ShipBar relay key is required.");
  }

  const path = routePath(request);
  const url = new URL(request.url);
  const repository = dependencies.repository;
  const ownerId = dependencies.ownerId;

  try {
    if (request.method === "GET" && path === "/health") {
      return json({ ok: true, service: "shipbar-relay" });
    }
    if (request.method === "GET" && path === "/tasks") {
      const query = url.searchParams.get("query")?.trim() ?? "";
      if (!query) throw new Error("query is required.");
      return json({ tasks: await repository.searchTasks(ownerId, query) });
    }
    if (request.method === "GET" && path === "/today") {
      return json({ tasks: await repository.getToday(ownerId) });
    }
    if (request.method === "POST" && path === "/captures") {
      const capture = await repository.enqueueCapture(
        ownerId,
        idempotencyKey(request),
        parseCapture(await body(request)),
      );
      return json({ capture }, 202);
    }
    if (request.method === "GET" && path === "/devices") {
      const now = (dependencies.now ?? (() => new Date()))();
      const devices = (await repository.listDevices(ownerId)).map((device) => ({
        ...device,
        online: isDeviceOnline(String(device.lastSeenAt ?? device.last_seen_at ?? ""), now),
      }));
      return json({ devices });
    }
    if (request.method === "POST" && path === "/executions") {
      const execution = await repository.enqueueExecution(
        ownerId,
        idempotencyKey(request),
        parseExecution(await body(request)),
      );
      return json({ execution }, 202);
    }
    if (request.method === "POST" && path === "/commands") {
      const payload = await body(request);
      requiredText(payload.deviceId, "deviceId");
      requiredText(payload.kind, "kind");
      if (!payload.payload || typeof payload.payload !== "object" || Array.isArray(payload.payload)) {
        throw new Error("payload must be an object.");
      }
      const command = await repository.enqueueCommand(ownerId, idempotencyKey(request), payload);
      return json({ command }, 202);
    }
    const commandMatch = path.match(/^\/commands\/([^/]+)$/);
    if (request.method === "GET" && commandMatch) {
      const command = await repository.getCommand(ownerId, decodeURIComponent(commandMatch[1]));
      return command ? json({ command }) : error(404, "not_found", "Command was not found.");
    }
    const executionMatch = path.match(/^\/executions\/([^/]+)$/);
    if (request.method === "GET" && executionMatch) {
      const execution = await repository.getExecution(ownerId, decodeURIComponent(executionMatch[1]));
      return execution ? json({ execution }) : error(404, "not_found", "Execution was not found.");
    }
    if (request.method === "POST" && path === "/sync/pull") {
      const payload = await body(request);
      return json(await repository.pull(ownerId, requiredText(payload.deviceId, "deviceId")));
    }
    if (request.method === "POST" && path === "/sync/push") {
      const payload = await body(request);
      requiredText(payload.deviceId, "deviceId");
      return json(await repository.push(ownerId, payload));
    }
    return error(404, "not_found", "Relay route was not found.");
  } catch (cause) {
    if (cause instanceof RelayConflictError) {
      return error(409, "idempotency_conflict", cause.message);
    }
    if (cause instanceof RelayStateConflictError) {
      return error(
        409,
        "state_conflict",
        "ShipBar relay state changed before this update; refresh and retry.",
      );
    }
    if (cause instanceof RelayStorageError) {
      return error(503, "service_unavailable", "ShipBar relay storage is temporarily unavailable.");
    }
    const message = cause instanceof Error ? cause.message : "Invalid request.";
    return error(400, "invalid_request", message);
  }
}
