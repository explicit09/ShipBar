import { assertEquals, assertRejects, assertThrows } from "jsr:@std/assert@1.0.14";
import * as domain from "./domain.ts";

Deno.test("relay domain exports its security and lifecycle contract", () => {
  assertEquals(typeof domain.hashRelayKey, "function");
  assertEquals(typeof domain.isAuthorized, "function");
  assertEquals(typeof domain.isDeviceOnline, "function");
  assertEquals(typeof domain.canTransitionExecution, "function");
  assertEquals(typeof domain.parseCapture, "function");
  assertEquals(typeof domain.parseExecution, "function");
});

Deno.test("relay keys use deterministic SHA-256 hashes and reject missing or wrong keys", async () => {
  const key = "ssssssssssssssssssssssssssssssss";
  const expected = "8fd6a6a78f5857d7ba1cfe9033bffeec86da2ba6a4bd60a6f833209d9d3e390d";
  assertEquals(await domain.hashRelayKey(key), expected);
  assertEquals(await domain.isAuthorized(key, expected), true);
  assertEquals(await domain.isAuthorized("wrong", expected), false);
  assertEquals(await domain.isAuthorized(null, expected), false);
  await assertRejects(() => domain.hashRelayKey("short"), Error, "at least 32");
});

Deno.test("device presence expires after 90 seconds", () => {
  const now = new Date("2026-07-13T12:00:00.000Z");
  assertEquals(domain.isDeviceOnline("2026-07-13T11:58:31.000Z", now), true);
  assertEquals(domain.isDeviceOnline("2026-07-13T11:58:30.000Z", now), true);
  assertEquals(domain.isDeviceOnline("2026-07-13T11:58:29.999Z", now), false);
  assertEquals(domain.isDeviceOnline("not-a-date", now), false);
});

Deno.test("execution lifecycle refuses invented or regressive status", () => {
  assertEquals(domain.canTransitionExecution("queued", "claimed"), true);
  assertEquals(domain.canTransitionExecution("claimed", "running"), true);
  assertEquals(domain.canTransitionExecution("running", "needs_review"), true);
  assertEquals(domain.canTransitionExecution("needs_review", "completed"), true);
  assertEquals(domain.canTransitionExecution("running", "failed"), true);
  assertEquals(domain.canTransitionExecution("claimed", "claimed"), true);
  assertEquals(domain.canTransitionExecution("running", "running"), true);
  assertEquals(domain.canTransitionExecution("queued", "running"), false);
  assertEquals(domain.canTransitionExecution("completed", "running"), false);
  assertEquals(domain.canTransitionExecution("unknown", "completed"), false);
});

Deno.test("capture validation trims text and defaults optional fields", () => {
  assertEquals(domain.parseCapture({ title: "  Write report  ", description: "  Detailed notes  " }), {
    title: "Write report",
    description: "Detailed notes",
    projectName: null,
    priority: "normal",
    dueAt: null,
  });
  assertThrows(() => domain.parseCapture({ title: " " }), Error, "title");
  assertThrows(() => domain.parseCapture({ title: "x", priority: "impossible" }), Error, "priority");
});

Deno.test("execution validation requires explicit task and device IDs", () => {
  assertEquals(domain.parseExecution({ taskId: " task-1 ", deviceId: " mac-1 ", instructions: " run tests " }), {
    taskId: "task-1",
    deviceId: "mac-1",
    repositoryPath: null,
    instructions: "run tests",
  });
  assertThrows(() => domain.parseExecution({ taskId: "task-1" }), Error, "deviceId");
});
