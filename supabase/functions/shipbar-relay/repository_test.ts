import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { RelayConflictError, RelayStateConflictError, SupabaseRelayRepository } from "./repository.ts";

function client(results: Record<string, { data: unknown; error: { code?: string; message: string } | null }>) {
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  return {
    calls,
    rpc(name: string, args: Record<string, unknown>) {
      calls.push({ name, args });
      return Promise.resolve(results[name] ?? { data: null, error: { message: `Unexpected RPC ${name}` } });
    },
    from() { throw new Error("non-atomic table operation used"); },
  };
}

Deno.test("capture idempotency mismatch is surfaced as a conflict without rewriting", async () => {
  const fake = client({ relay_enqueue_capture: {
    data: null,
    error: { code: "22000", message: "Idempotency key was already used with a different capture payload." },
  } });
  const repository = new SupabaseRelayRepository(fake as never);

  await assertRejects(
    () => repository.enqueueCapture("owner", "same-key", { title: "changed" }),
    RelayConflictError,
  );
  assertEquals(fake.calls[0]?.name, "relay_enqueue_capture");
});

Deno.test("execution idempotency mismatch is surfaced as a conflict without rewriting", async () => {
  const fake = client({ relay_enqueue_execution: {
    data: null,
    error: { code: "22000", message: "Idempotency key was already used with a different execution payload." },
  } });
  const repository = new SupabaseRelayRepository(fake as never);

  await assertRejects(
    () => repository.enqueueExecution("owner", "same-key", { taskId: "changed", deviceId: "mac" }),
    RelayConflictError,
  );
});

Deno.test("pull delegates claim predicates to one atomic database RPC", async () => {
  const fake = client({ relay_claim_work: {
    data: { device_id: "mac", captures: [], executions: [] }, error: null,
  } });
  const repository = new SupabaseRelayRepository(fake as never);

  const result = await repository.pull("owner", "mac");

  assertEquals(result.deviceId, "mac");
  assertEquals(fake.calls.map((call) => call.name), ["relay_claim_work"]);
});

Deno.test("stale or wrong-device execution transitions fail closed", async () => {
  const fake = client({ relay_transition_execution: {
    data: null, error: { code: "P0001", message: "Execution transition lost a status or device compare-and-swap." },
  } });
  const repository = new SupabaseRelayRepository(fake as never);

  await assertRejects(
    () => repository.push("owner", {
      deviceId: "wrong-mac",
      executionUpdates: [{ executionId: "00000000-0000-0000-0000-000000000001", expectedStatus: "claimed", status: "running" }],
    }),
    RelayStateConflictError,
  );
  assertEquals(fake.calls[0]?.name, "relay_transition_execution");
});

Deno.test("wrong-device capture acknowledgements surface a state conflict", async () => {
  const fake = client({ relay_ack_capture: {
    data: null, error: { code: "P0001", message: "Capture acknowledgement lost its claim compare-and-swap." },
  } });
  const repository = new SupabaseRelayRepository(fake as never);

  await assertRejects(
    () => repository.push("owner", {
      deviceId: "wrong-mac",
      captureAcknowledgements: [{
        captureId: "00000000-0000-0000-0000-000000000001",
        taskId: "task-1",
      }],
    }),
    RelayStateConflictError,
  );
  assertEquals(fake.calls[0]?.name, "relay_ack_capture");
});
