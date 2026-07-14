import { assertEquals } from "jsr:@std/assert@1.0.14";
import { hashRelayKey } from "./domain.ts";
import { handleRelayRequest, type RelayRepository } from "./router.ts";
import { RelayConflictError, RelayStateConflictError, RelayStorageError } from "./repository.ts";

class FakeRepository implements RelayRepository {
  captures: Array<Record<string, unknown>> = [];
  executions: Array<Record<string, unknown>> = [];
  commands: Array<Record<string, unknown>> = [];

  searchTasks(_ownerId: string, query: string) {
    return Promise.resolve([{ taskId: "t1", title: `match:${query}` }]);
  }
  getToday() {
    return Promise.resolve([{ taskId: "today", title: "Today" }]);
  }
  enqueueCapture(ownerId: string, idempotencyKey: string, input: Record<string, unknown>) {
    const existing = this.captures.find((item) => item.idempotencyKey === idempotencyKey);
    if (existing) return Promise.resolve(existing);
    const item = { id: `c${this.captures.length + 1}`, ownerId, idempotencyKey, status: "queued", ...input };
    this.captures.push(item);
    return Promise.resolve(item);
  }
  listDevices() {
    return Promise.resolve([
      { deviceId: "mac-1", name: "Mac", lastSeenAt: "2026-07-13T11:59:30.000Z" },
      { deviceId: "old", name: "Old Mac", lastSeenAt: "2026-07-13T11:00:00.000Z" },
    ]);
  }
  enqueueExecution(ownerId: string, idempotencyKey: string, input: Record<string, unknown>) {
    const item = { id: "e1", ownerId, idempotencyKey, status: "queued", ...input };
    this.executions.push(item);
    return Promise.resolve(item);
  }
  getExecution(_ownerId: string, executionId: string) {
    return Promise.resolve(executionId === "e1" ? this.executions[0] ?? null : null);
  }
  enqueueCommand(ownerId: string, idempotencyKey: string, input: Record<string, unknown>) {
    const existing = this.commands.find((item) => item.idempotencyKey === idempotencyKey);
    if (existing) return Promise.resolve(existing);
    const item = { id: `m${this.commands.length + 1}`, ownerId, idempotencyKey, status: "queued", ...input };
    this.commands.push(item);
    return Promise.resolve(item);
  }
  getCommand(_ownerId: string, commandId: string) {
    return Promise.resolve(this.commands.find((item) => item.id === commandId) ?? null);
  }
  pull(ownerId: string, deviceId: string) {
    return Promise.resolve({ ownerId, deviceId, captures: [], executions: [] });
  }
  push(_ownerId: string, payload: Record<string, unknown>) {
    return Promise.resolve({ accepted: true, payload });
  }
}

const key = "kkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkk";
const keyHash = await hashRelayKey(key);
const now = () => new Date("2026-07-13T12:00:00.000Z");

function request(path: string, init: RequestInit = {}, authenticated = true): Request {
  const headers = new Headers(init.headers);
  if (authenticated) headers.set("X-ShipBar-Key", key);
  if (init.body) headers.set("Content-Type", "application/json");
  return new Request(`http://localhost/shipbar-relay${path}`, { ...init, headers });
}

async function call(path: string, init: RequestInit = {}, authenticated = true) {
  const repository = new FakeRepository();
  const response = await handleRelayRequest(request(path, init, authenticated), {
    ownerId: "owner-1",
    keyHash,
    repository,
    now,
  });
  return { response, body: await response.json(), repository };
}

Deno.test("relay rejects missing and incorrect keys before routing", async () => {
  assertEquals((await call("/health", {}, false)).response.status, 401);
  const wrong = await handleRelayRequest(
    new Request("http://localhost/shipbar-relay/health", { headers: { "X-ShipBar-Key": "wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww" } }),
    { ownerId: "owner-1", keyHash, repository: new FakeRepository(), now },
  );
  assertEquals(wrong.status, 401);
});

Deno.test("health returns authenticated relay state", async () => {
  const { response, body } = await call("/health");
  assertEquals(response.status, 200);
  assertEquals(body, { ok: true, service: "shipbar-relay" });
});

Deno.test("capture requires idempotency and returns the same durable queue item", async () => {
  const repository = new FakeRepository();
  const dependencies = { ownerId: "owner-1", keyHash, repository, now };
  const init = {
    method: "POST",
    headers: { "Idempotency-Key": "capture-1" },
    body: JSON.stringify({ title: " Test task " }),
  };
  const first = await handleRelayRequest(request("/captures", init), dependencies);
  const second = await handleRelayRequest(request("/captures", init), dependencies);
  assertEquals(first.status, 202);
  assertEquals((await first.json()).capture.id, "c1");
  assertEquals((await second.json()).capture.id, "c1");
  assertEquals(repository.captures.length, 1);
  assertEquals((await call("/captures", { method: "POST", body: JSON.stringify({ title: "x" }) })).response.status, 400);
});

Deno.test("task search, today, and device presence expose compact truthful data", async () => {
  assertEquals((await call("/tasks?query=report")).body.tasks[0].title, "match:report");
  assertEquals((await call("/today")).body.tasks[0].taskId, "today");
  const devices = (await call("/devices")).body.devices;
  assertEquals(devices[0].online, true);
  assertEquals(devices[1].online, false);
});

Deno.test("execution queue requires explicit device and stays queued", async () => {
  const missing = await call("/executions", {
    method: "POST",
    headers: { "Idempotency-Key": "execution-1" },
    body: JSON.stringify({ taskId: "t1" }),
  });
  assertEquals(missing.response.status, 400);
  const queued = await call("/executions", {
    method: "POST",
    headers: { "Idempotency-Key": "execution-1" },
    body: JSON.stringify({ taskId: "t1", deviceId: "mac-1" }),
  });
  assertEquals(queued.response.status, 202);
  assertEquals(queued.body.execution.status, "queued");
});

Deno.test("productivity commands are durable, idempotent, and expose truthful status", async () => {
  const repository = new FakeRepository();
  const dependencies = { ownerId: "owner-1", keyHash, repository, now };
  const init = {
    method: "POST",
    headers: { "Idempotency-Key": "command-create-project-1" },
    body: JSON.stringify({
      deviceId: "mac-1",
      kind: "createProject",
      payload: { kind: "createProject", project: { name: "ChatGPT QA" } },
    }),
  };
  const first = await handleRelayRequest(request("/commands", init), dependencies);
  const second = await handleRelayRequest(request("/commands", init), dependencies);
  assertEquals(first.status, 202);
  assertEquals((await first.json()).command.status, "queued");
  assertEquals((await second.json()).command.id, "m1");
  assertEquals(repository.commands.length, 1);

  const status = await handleRelayRequest(request("/commands/m1"), dependencies);
  assertEquals((await status.json()).command.id, "m1");
});

Deno.test("internal sync routes accept device pull and push only with valid bodies", async () => {
  const pulled = await call("/sync/pull", { method: "POST", body: JSON.stringify({ deviceId: "mac-1" }) });
  assertEquals(pulled.body.deviceId, "mac-1");
  const pushed = await call("/sync/push", {
    method: "POST",
    body: JSON.stringify({ deviceId: "mac-1", heartbeat: { name: "Mac", platform: "macos" } }),
  });
  assertEquals(pushed.body.accepted, true);
});

Deno.test("idempotency payload reuse returns conflict", async () => {
  const repository = new FakeRepository();
  repository.enqueueCapture = () => Promise.reject(new RelayConflictError("payload differs"));
  const response = await handleRelayRequest(request("/captures", {
    method: "POST",
    headers: { "Idempotency-Key": "capture-conflict" },
    body: JSON.stringify({ title: "Changed" }),
  }), { ownerId: "owner-1", keyHash, repository, now });

  assertEquals(response.status, 409);
  assertEquals((await response.json()).error, "idempotency_conflict");
});

Deno.test("storage failures are sanitized as unavailable", async () => {
  const repository = new FakeRepository();
  repository.getToday = () => Promise.reject(new RelayStorageError("database password leaked here"));
  const response = await handleRelayRequest(request("/today"), {
    ownerId: "owner-1", keyHash, repository, now,
  });

  assertEquals(response.status, 503);
  assertEquals(await response.json(), {
    error: "service_unavailable",
    message: "ShipBar relay storage is temporarily unavailable.",
  });
});

Deno.test("compare-and-swap failures are sanitized as conflicts", async () => {
  const repository = new FakeRepository();
  repository.push = () => Promise.reject(
    new RelayStateConflictError("Execution transition leaked internal database details."),
  );
  const response = await handleRelayRequest(request("/sync/push", {
    method: "POST",
    body: JSON.stringify({ deviceId: "mac-1" }),
  }), { ownerId: "owner-1", keyHash, repository, now });

  assertEquals(response.status, 409);
  assertEquals(await response.json(), {
    error: "state_conflict",
    message: "ShipBar relay state changed before this update; refresh and retry.",
  });
});
