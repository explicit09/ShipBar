import { describe, expect, it } from "vitest";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { resolveCapabilities, WRITE_ENABLED_SURFACES } from "../src/capabilities.js";
import { ShipbarClient, type ShipbarRunner } from "../src/shipbar-client.js";
import { createShipbarServer } from "../src/server.js";

const idleRunner: ShipbarRunner = {
  async run() {
    return {
      stdout: JSON.stringify({
        requestID: "r",
        schemaVersion: 1,
        createdAt: "2026-07-12T00:00:00Z",
        result: { type: "acknowledged" },
      }),
      stderr: "",
      exitCode: 0,
    };
  },
};

async function toolNames(surface: string, env: Record<string, string>) {
  const server = createShipbarServer({
    shipbar: new ShipbarClient({ runner: idleRunner }),
    surface,
    env,
  });
  const client = new Client({ name: "test", version: "0.0.0" });
  const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair();
  await Promise.all([server.connect(serverTransport), client.connect(clientTransport)]);
  const tools = await client.listTools();
  return tools.tools;
}

const WRITE_TOOLS = ["create_task", "update_task", "complete_task", "prepare_run"];

describe("capability gating", () => {
  it("personal-pro registers zero write tools", async () => {
    const tools = await toolNames("personal-pro", { SHIPBAR_ENABLE_MCP_WRITES: "1" });
    const names = tools.map((tool) => tool.name);
    for (const writeTool of WRITE_TOOLS) {
      expect(names).not.toContain(writeTool);
    }
  });

  it("unknown surfaces fail closed", () => {
    expect(resolveCapabilities("mystery-surface", { SHIPBAR_ENABLE_MCP_WRITES: "1" }).writesEnabled)
      .toBe(false);
    expect(resolveCapabilities("", {}).writesEnabled).toBe(false);
  });

  it("writes need both a supported surface and the explicit env flag", () => {
    const surface = [...WRITE_ENABLED_SURFACES][0];
    expect(resolveCapabilities(surface, {}).writesEnabled).toBe(false);
    expect(resolveCapabilities(surface, { SHIPBAR_ENABLE_MCP_WRITES: "1" }).writesEnabled).toBe(true);
    expect(resolveCapabilities("personal-pro", { SHIPBAR_ENABLE_MCP_WRITES: "1" }).writesEnabled)
      .toBe(false);
  });

  it("capabilities are immutable", () => {
    const capability = resolveCapabilities("personal-pro", {});
    expect(Object.isFrozen(capability)).toBe(true);
  });

  it("a write-enabled surface registers the write adapters with honest annotations", async () => {
    const surface = [...WRITE_ENABLED_SURFACES][0];
    const tools = await toolNames(surface, { SHIPBAR_ENABLE_MCP_WRITES: "1" });
    const names = tools.map((tool) => tool.name);
    for (const writeTool of WRITE_TOOLS) {
      expect(names).toContain(writeTool);
    }
    for (const tool of tools.filter((candidate) => WRITE_TOOLS.includes(candidate.name))) {
      expect(tool.annotations?.readOnlyHint).toBe(false);
      expect(typeof tool.description).toBe("string");
      expect(tool.description ?? "").toMatch(/confirm/i);
    }
    const complete = tools.find((tool) => tool.name === "complete_task");
    expect(complete?.annotations?.destructiveHint).toBe(true);
  });

  it("write handlers reached indirectly return a capability error", async () => {
    const server = createShipbarServer({
      shipbar: new ShipbarClient({ runner: idleRunner }),
      surface: [...WRITE_ENABLED_SURFACES][0],
      env: { SHIPBAR_ENABLE_MCP_WRITES: "1" },
    });
    const client = new Client({ name: "test", version: "0.0.0" });
    const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair();
    await Promise.all([server.connect(serverTransport), client.connect(clientTransport)]);

    const result = await client.callTool({
      name: "create_task",
      arguments: { title: "New task" },
    });
    expect(result.isError).toBe(true);
    expect(JSON.stringify(result.content)).toMatch(/not.*supported|capability/i);
  });
});
