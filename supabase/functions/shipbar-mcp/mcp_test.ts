import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import { handleMcpRequest, type McpDependencies } from "./mcp.ts";
import type { RelayRepository } from "../shipbar-relay/router.ts";

class FakeRepository implements RelayRepository {
  captures: Array<Record<string, unknown>> = [];
  executions: Array<Record<string, unknown>> = [];

  searchTasks(_ownerId: string, query: string) {
    return Promise.resolve([{
      taskId: "task-1",
      title: `match:${query}`,
      promptSnapshot: "secret",
    }]);
  }
  getToday() {
    return Promise.resolve([{ taskId: "today-1", title: "Today" }]);
  }
  enqueueCapture(
    ownerId: string,
    idempotencyKey: string,
    input: Record<string, unknown>,
  ) {
    const item = {
      id: "capture-1",
      ownerId,
      idempotencyKey,
      status: "queued",
      ...input,
    };
    this.captures.push(item);
    return Promise.resolve(item);
  }
  listDevices() {
    return Promise.resolve([
      {
        deviceId: "mac-1",
        name: "Mac",
        platform: "macos",
        lastSeenAt: "2026-07-14T12:00:00Z",
      },
    ]);
  }
  enqueueExecution(
    ownerId: string,
    idempotencyKey: string,
    input: Record<string, unknown>,
  ) {
    const item = {
      id: "execution-1",
      ownerId,
      idempotencyKey,
      status: "queued",
      ...input,
    };
    this.executions.push(item);
    return Promise.resolve(item);
  }
  getExecution(_ownerId: string, executionId: string) {
    return Promise.resolve(
      executionId === "execution-1" ? this.executions[0] ?? null : null,
    );
  }
  pull() {
    return Promise.resolve({ captures: [], executions: [] });
  }
  push() {
    return Promise.resolve({ accepted: true });
  }
}

function dependencies(authorized = true): McpDependencies {
  return {
    ownerId: "owner-1",
    resourceUrl: "https://example.test/functions/v1/shipbar-mcp",
    authorizationServer: "https://example.test/auth/v1",
    repository: new FakeRepository(),
    authorize: () => Promise.resolve(authorized),
    now: () => new Date("2026-07-14T12:00:30Z"),
  };
}

function request(
  method: string,
  params?: Record<string, unknown>,
  token?: string,
  id = 1,
): Request {
  const headers = new Headers({
    "Content-Type": "application/json",
    Accept: "application/json, text/event-stream",
  });
  if (token) headers.set("Authorization", `Bearer ${token}`);
  return new Request("https://example.test/functions/v1/shipbar-mcp", {
    method: "POST",
    headers,
    body: JSON.stringify({ jsonrpc: "2.0", id, method, params }),
  });
}

Deno.test("MCP initialization advertises tools and owner-safe server instructions", async () => {
  const response = await handleMcpRequest(
    request("initialize", {
      protocolVersion: "2025-06-18",
      capabilities: {},
      clientInfo: { name: "test", version: "1" },
    }),
    dependencies(),
  );
  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.result.protocolVersion, "2025-06-18");
  assertEquals(body.result.capabilities, { tools: { listChanged: false } });
  assertStringIncludes(body.result.instructions, "queued");
});

Deno.test("tools/list is anonymous, complete, and marks every tool OAuth protected", async () => {
  const response = await handleMcpRequest(
    request("tools/list"),
    dependencies(false),
  );
  const body = await response.json();
  const tools = body.result.tools as Array<Record<string, unknown>>;
  assertEquals(tools.map((tool) => tool.name), [
    "search_tasks",
    "get_today",
    "list_devices",
    "create_task",
    "queue_execution",
    "get_execution_status",
  ]);
  for (const tool of tools) {
    assertEquals(
      (tool.securitySchemes as Array<Record<string, unknown>>)[0].type,
      "oauth2",
    );
    assertEquals(
      (tool._meta as Record<string, unknown>).securitySchemes,
      tool.securitySchemes,
    );
  }
  assertEquals(
    (tools[0].annotations as Record<string, unknown>).readOnlyHint,
    true,
  );
  assertEquals(
    (tools[3].annotations as Record<string, unknown>).readOnlyHint,
    false,
  );
});

Deno.test("unauthenticated tool calls return the MCP OAuth challenge without touching storage", async () => {
  const deps = dependencies(false);
  const response = await handleMcpRequest(
    request("tools/call", {
      name: "get_today",
      arguments: {},
    }),
    deps,
  );
  const body = await response.json();
  assertEquals(body.result.isError, true);
  assertStringIncludes(
    body.result._meta["mcp/www_authenticate"][0],
    "oauth-protected-resource",
  );
});

Deno.test("authenticated reads strip unknown private mirror fields", async () => {
  const response = await handleMcpRequest(
    request("tools/call", {
      name: "search_tasks",
      arguments: { query: "report" },
    }, "valid"),
    dependencies(),
  );
  const body = await response.json();
  assertEquals(body.result.structuredContent.tasks[0].title, "match:report");
  assertEquals(
    "promptSnapshot" in body.result.structuredContent.tasks[0],
    false,
  );
});

Deno.test("create_task durably queues all supported details and reports queued, not delivered", async () => {
  const deps = dependencies();
  const response = await handleMcpRequest(
    request("tools/call", {
      name: "create_task",
      arguments: {
        idempotencyKey: "chatgpt-create-123",
        title: "Prepare brief",
        description: "Include the launch evidence.",
        projectName: "ShipBar",
        priority: "high",
        dueAt: "2026-07-15T17:00:00Z",
      },
    }, "valid"),
    deps,
  );
  const body = await response.json();
  assertEquals(body.result.structuredContent.capture.status, "queued");
  assertStringIncludes(body.result.content[0].text, "queued");
  assertEquals(
    (deps.repository as FakeRepository).captures[0].title,
    "Prepare brief",
  );
});

Deno.test("execution queue stays truthful and status is fetched separately", async () => {
  const deps = dependencies();
  const queued = await handleMcpRequest(
    request("tools/call", {
      name: "queue_execution",
      arguments: {
        idempotencyKey: "chatgpt-run-123",
        taskId: "task-1",
        deviceId: "mac-1",
        repositoryPath: "/Users/me/Projects/ShipBar",
        instructions: "Run the full checks.",
      },
    }, "valid"),
    deps,
  );
  assertEquals(
    (await queued.json()).result.structuredContent.execution.status,
    "queued",
  );

  const status = await handleMcpRequest(
    request(
      "tools/call",
      {
        name: "get_execution_status",
        arguments: { executionId: "execution-1" },
      },
      "valid",
      2,
    ),
    deps,
  );
  assertEquals(
    (await status.json()).result.structuredContent.execution.status,
    "queued",
  );
});

Deno.test("protected resource metadata points ChatGPT to the Supabase OAuth server", async () => {
  const response = await handleMcpRequest(
    new Request(
      "https://example.test/functions/v1/shipbar-mcp/.well-known/oauth-protected-resource",
    ),
    dependencies(),
  );
  assertEquals(response.status, 200);
  assertEquals(await response.json(), {
    resource: "https://example.test/functions/v1/shipbar-mcp",
    authorization_servers: ["https://example.test/auth/v1"],
    scopes_supported: ["shipbar.read", "shipbar.write"],
  });
});
