import { describe, expect, it } from "vitest";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { ShipbarClient, ShipbarUnavailableError, type ShipbarRunner } from "../src/shipbar-client.js";
import { createShipbarServer } from "../src/server.js";

function runnerReturning(json: unknown, exitCode = 0): ShipbarRunner {
  return {
    async run() {
      return { stdout: JSON.stringify(json), stderr: "", exitCode };
    },
  };
}

function envelope(result: unknown): unknown {
  return {
    requestID: "req-1",
    schemaVersion: 1,
    createdAt: "2026-07-12T00:00:00Z",
    result,
  };
}

async function connectedClient(runner: ShipbarRunner) {
  const server = createShipbarServer({
    shipbar: new ShipbarClient({ runner }),
    surface: "personal-pro",
    env: {},
  });
  const client = new Client({ name: "test", version: "0.0.0" });
  const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair();
  await Promise.all([server.connect(serverTransport), client.connect(clientTransport)]);
  return client;
}

const taskSummary = {
  taskID: "t1",
  title: "Fix login",
  taskDescription: "Details",
  status: "todo",
  priority: "high",
  type: "bug",
  projectName: "Website",
  dueDate: null,
  focusDate: null,
  focusOrder: null,
  isInbox: false,
  updatedAt: "2026-07-12T00:00:00Z",
};

describe("read tools", () => {
  it("registers exactly the five read tools on personal-pro", async () => {
    const client = await connectedClient(runnerReturning(envelope({ type: "tasks", tasks: [] })));
    const tools = await client.listTools();
    expect(tools.tools.map((tool) => tool.name).sort()).toEqual([
      "get_run_status",
      "get_task",
      "get_today",
      "list_prepared_runs",
      "search_tasks",
    ]);
    for (const tool of tools.tools) {
      expect(tool.annotations?.readOnlyHint).toBe(true);
    }
  });

  it("search_tasks returns matched tasks and supports empty results", async () => {
    const client = await connectedClient(
      runnerReturning(envelope({ type: "tasks", tasks: [taskSummary] })),
    );
    const result = await client.callTool({ name: "search_tasks", arguments: { query: "login" } });
    const payload = result.structuredContent as { tasks: Array<{ title: string }> };
    expect(payload.tasks).toHaveLength(1);
    expect(payload.tasks[0].title).toBe("Fix login");

    const emptyClient = await connectedClient(runnerReturning(envelope({ type: "tasks", tasks: [] })));
    const empty = await emptyClient.callTool({ name: "search_tasks", arguments: { query: "nope" } });
    expect((empty.structuredContent as { tasks: unknown[] }).tasks).toHaveLength(0);
  });

  it("get_today and get_task surface task summaries", async () => {
    const client = await connectedClient(
      runnerReturning(envelope({ type: "tasks", tasks: [taskSummary] })),
    );
    const today = await client.callTool({ name: "get_today", arguments: {} });
    expect((today.structuredContent as { tasks: unknown[] }).tasks).toHaveLength(1);

    const task = await client.callTool({ name: "get_task", arguments: { taskId: "t1" } });
    expect((task.structuredContent as { tasks: Array<{ taskID: string }> }).tasks[0].taskID).toBe("t1");
  });

  it("list_prepared_runs and get_run_status never expose prompt fields", async () => {
    const runWithPromptLeak = {
      runID: "r1",
      taskID: "t1",
      taskTitle: "Fix login",
      projectName: "Website",
      repositoryPath: "/Users/me/Projects/site",
      status: "prepared",
      updatedAt: "2026-07-12T00:00:00Z",
      promptSnapshot: "SECRET PROMPT BODY",
    };
    const listClient = await connectedClient(
      runnerReturning(envelope({ type: "preparedRuns", runs: [runWithPromptLeak] })),
    );
    const runs = await listClient.callTool({ name: "list_prepared_runs", arguments: {} });
    expect(JSON.stringify(runs)).not.toContain("SECRET PROMPT BODY");
    expect((runs.structuredContent as { runs: Array<{ runID: string }> }).runs[0].runID).toBe("r1");

    const statusClient = await connectedClient(
      runnerReturning(envelope({ type: "runStatus", run: runWithPromptLeak })),
    );
    const status = await statusClient.callTool({ name: "get_run_status", arguments: { runId: "r1" } });
    expect(JSON.stringify(status)).not.toContain("SECRET PROMPT BODY");
    expect((status.structuredContent as { run: { status: string } }).run.status).toBe("prepared");
  });

  it("helper timeouts become an actionable unavailable error", async () => {
    const timeoutRunner: ShipbarRunner = {
      async run() {
        return { stdout: "", stderr: "shipbarctl: Timed out after 15s.", exitCode: 3 };
      },
    };
    const client = await connectedClient(timeoutRunner);
    const result = await client.callTool({ name: "get_today", arguments: {} });
    expect(result.isError).toBe(true);
    expect(JSON.stringify(result.content)).toContain("ShipBar");
  });

  it("invalid helper JSON is a truthful error, not fabricated data", async () => {
    const client = await connectedClient({
      async run() {
        return { stdout: "not-json{", stderr: "", exitCode: 0 };
      },
    });
    const result = await client.callTool({ name: "search_tasks", arguments: { query: "x" } });
    expect(result.isError).toBe(true);
  });

  it("the client rejects oversized helper output", async () => {
    const shipbar = new ShipbarClient({
      runner: {
        async run() {
          return { stdout: "x".repeat(20_000_000), stderr: "", exitCode: 0 };
        },
      },
      maxOutputBytes: 1_000_000,
    });
    await expect(shipbar.call(["list-prepared"])).rejects.toThrow(ShipbarUnavailableError);
  });
});
