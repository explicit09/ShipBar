import type { SupabaseClient } from "npm:@supabase/supabase-js@2.110.3";
import type { RelayRepository } from "./router.ts";

type JsonObject = Record<string, unknown>;

export class RelayConflictError extends Error {}
export class RelayStorageError extends Error {}

function camelKey(key: string): string {
  return key.replace(/_([a-z])/g, (_, letter: string) => letter.toUpperCase());
}

function camelize(row: JsonObject): JsonObject {
  return Object.fromEntries(
    Object.entries(row)
      .filter(([key]) => key !== "owner_id" && key !== "api_key_hash" && key !== "search_document")
      .map(([key, value]) => [camelKey(key), value]),
  );
}

function record(value: unknown, name: string): JsonObject {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error(`${name} must be an object.`);
  return value as JsonObject;
}

function records(value: unknown): JsonObject[] {
  if (value === undefined) return [];
  if (!Array.isArray(value)) throw new Error("Expected an array.");
  return value.map((item) => record(item, "Array item"));
}

function text(value: unknown, name: string): string {
  if (typeof value !== "string" || value.trim() === "") throw new Error(`${name} is required.`);
  return value.trim();
}

export class SupabaseRelayRepository implements RelayRepository {
  constructor(private readonly client: SupabaseClient) {}

  private unwrap<T>(result: { data: T | null; error: { message: string } | null }): T {
    if (result.error) {
      const code = "code" in result.error ? String(result.error.code) : "";
      if (code === "22000") throw new RelayConflictError(result.error.message);
      throw new RelayStorageError(result.error.message);
    }
    if (result.data === null) throw new RelayStorageError("Relay database returned no data.");
    return result.data;
  }

  async searchTasks(ownerId: string, query: string): Promise<JsonObject[]> {
    const data = this.unwrap(await this.client.from("task_mirrors")
      .select("task_id,title,description,status,priority,project_name,due_at,focus_date,focus_order,is_inbox,source_updated_at")
      .eq("owner_id", ownerId)
      .textSearch("search_document", query, { config: "simple", type: "websearch" })
      .order("source_updated_at", { ascending: false })
      .limit(50));
    return (data as JsonObject[]).map(camelize);
  }

  async getToday(ownerId: string): Promise<JsonObject[]> {
    const today = new Date().toISOString().slice(0, 10);
    const data = this.unwrap(await this.client.from("task_mirrors")
      .select("task_id,title,description,status,priority,project_name,due_at,focus_date,focus_order,is_inbox,source_updated_at")
      .eq("owner_id", ownerId)
      .eq("focus_date", today)
      .order("focus_order", { ascending: true, nullsFirst: false }));
    return (data as JsonObject[]).map(camelize);
  }

  async enqueueCapture(ownerId: string, idempotencyKey: string, input: JsonObject): Promise<JsonObject> {
    const data = this.unwrap(await this.client.rpc("relay_enqueue_capture", {
      p_owner_id: ownerId,
      p_idempotency_key: idempotencyKey,
      p_title: input.title,
      p_description: input.description ?? "",
      p_project_name: input.projectName ?? null,
      p_priority: input.priority ?? "normal",
      p_due_at: input.dueAt ?? null,
    }));
    return camelize(record(data, "capture"));
  }

  async listDevices(ownerId: string): Promise<JsonObject[]> {
    const data = this.unwrap(await this.client.from("devices")
      .select("device_id,name,platform,capabilities,last_seen_at")
      .eq("owner_id", ownerId)
      .order("last_seen_at", { ascending: false }));
    return (data as JsonObject[]).map(camelize);
  }

  async enqueueExecution(ownerId: string, idempotencyKey: string, input: JsonObject): Promise<JsonObject> {
    const data = this.unwrap(await this.client.rpc("relay_enqueue_execution", {
      p_owner_id: ownerId,
      p_idempotency_key: idempotencyKey,
      p_task_id: input.taskId,
      p_device_id: input.deviceId,
      p_repository_path: input.repositoryPath ?? null,
      p_instructions: input.instructions ?? "",
    }));
    return camelize(record(data, "execution"));
  }

  async getExecution(ownerId: string, executionId: string): Promise<JsonObject | null> {
    const { data, error } = await this.client.from("execution_queue")
      .select("id,task_id,device_id,status,local_run_id,result_summary,lease_expires_at,created_at,updated_at")
      .eq("owner_id", ownerId)
      .eq("id", executionId)
      .maybeSingle();
    if (error) throw new RelayStorageError(error.message);
    return data ? camelize(data as JsonObject) : null;
  }

  async pull(ownerId: string, deviceId: string): Promise<JsonObject> {
    const now = new Date();
    const leaseExpiresAt = new Date(now.getTime() + 60_000).toISOString();
    const data = record(this.unwrap(await this.client.rpc("relay_claim_work", {
      p_owner_id: ownerId,
      p_device_id: deviceId,
      p_now: now.toISOString(),
      p_lease_expires_at: leaseExpiresAt,
    })), "claim result");
    return {
      deviceId: data.device_id,
      leaseExpiresAt: data.lease_expires_at,
      captures: records(data.captures).map(camelize),
      executions: records(data.executions).map(camelize),
    };
  }

  async push(ownerId: string, payload: JsonObject): Promise<JsonObject> {
    const deviceId = text(payload.deviceId, "deviceId");
    const now = new Date().toISOString();
    if (payload.heartbeat) {
      const heartbeat = record(payload.heartbeat, "heartbeat");
      this.unwrap(await this.client.from("devices").upsert({
        owner_id: ownerId,
        device_id: deviceId,
        name: text(heartbeat.name, "heartbeat.name"),
        platform: text(heartbeat.platform, "heartbeat.platform"),
        capabilities: Array.isArray(heartbeat.capabilities) ? heartbeat.capabilities : [],
        last_seen_at: now,
        updated_at: now,
      }, { onConflict: "owner_id,device_id" }).select("id"));
    }
    const mirrors = records(payload.taskMirrors).map((item) => ({
      owner_id: ownerId,
      task_id: text(item.taskId, "taskMirror.taskId"),
      title: text(item.title, "taskMirror.title"),
      description: typeof item.description === "string" ? item.description : "",
      status: text(item.status, "taskMirror.status"),
      priority: typeof item.priority === "string" ? item.priority : "normal",
      project_name: item.projectName ?? null,
      due_at: item.dueAt ?? null,
      focus_date: item.focusDate ?? null,
      focus_order: item.focusOrder ?? null,
      is_inbox: item.isInbox !== false,
      source_updated_at: text(item.updatedAt, "taskMirror.updatedAt"),
      synced_at: now,
    }));
    if (mirrors.length > 0) {
      this.unwrap(await this.client.from("task_mirrors")
        .upsert(mirrors, { onConflict: "owner_id,task_id" }).select("id"));
    }
    for (const acknowledgement of records(payload.captureAcknowledgements)) {
      const captureId = text(acknowledgement.captureId, "captureAcknowledgement.captureId");
      const deliveredTaskId = text(acknowledgement.taskId, "captureAcknowledgement.taskId");
      this.unwrap(await this.client.rpc("relay_ack_capture", {
        p_owner_id: ownerId, p_device_id: deviceId, p_capture_id: captureId,
        p_task_id: deliveredTaskId, p_now: now,
      }));
    }
    for (const update of records(payload.executionUpdates)) {
      const executionId = text(update.executionId, "executionUpdate.executionId");
      const nextStatus = text(update.status, "executionUpdate.status");
      const expectedStatus = text(update.expectedStatus, "executionUpdate.expectedStatus");
      this.unwrap(await this.client.rpc("relay_transition_execution", {
        p_owner_id: ownerId, p_device_id: deviceId, p_execution_id: executionId,
        p_expected_status: expectedStatus, p_next_status: nextStatus,
        p_local_run_id: update.localRunId ?? null,
        p_result_summary: update.resultSummary ?? null, p_now: now,
      }));
    }
    return { accepted: true, acceptedAt: now };
  }
}
