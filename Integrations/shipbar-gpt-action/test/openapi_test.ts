import { assert, assertEquals, assertMatch, assertStringIncludes } from "jsr:@std/assert@1.0.14";

const schemaPath = new URL("../openapi.yaml", import.meta.url);
const schema = await Deno.readTextFile(schemaPath).catch(() => "");

Deno.test("GPT Action schema exposes the six personal relay operations", () => {
  for (const operationId of [
    "searchShipBarTasks",
    "getShipBarToday",
    "queueShipBarCapture",
    "listShipBarDevices",
    "queueShipBarExecution",
    "getShipBarExecutionStatus",
  ]) {
    assertStringIncludes(schema, `operationId: ${operationId}`);
  }
  assertEquals((schema.match(/operationId:/g) ?? []).length, 6);
});

Deno.test("GPT Action uses a private custom-header API key", () => {
  assertMatch(schema, /type:\s*apiKey/);
  assertMatch(schema, /in:\s*header/);
  assertMatch(schema, /name:\s*X-ShipBar-Key/);
  assertStringIncludes(schema, "security:\n  - ShipBarKey: []");
});

Deno.test("mutations require idempotency and describe confirmation boundaries", () => {
  assertEquals((schema.match(/\$ref:\s*"#\/components\/parameters\/IdempotencyKey"/g) ?? []).length, 2);
  assertEquals((schema.match(/name:\s*Idempotency-Key/g) ?? []).length, 1);
  assertEquals((schema.match(/x-openai-isConsequential:\s*true/g) ?? []).length, 2);
  assertStringIncludes(schema.toLowerCase(), "confirm");
  assertStringIncludes(schema.toLowerCase(), "queued does not mean running");
});

Deno.test("internal device sync routes are not exposed to ChatGPT", () => {
  assert(!schema.includes("/sync/pull"));
  assert(!schema.includes("/sync/push"));
});
