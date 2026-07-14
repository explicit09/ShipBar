import type { SupabaseClient } from "npm:@supabase/supabase-js@2.110.3";
import { canTransitionExecution } from "./domain.ts";
import type { RelayRepository } from "./router.ts";

type JsonObject = Record<string, unknown>;

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
    if (result.error) throw new Error(result.error.message);
    if (result.data === null) throw new Error("Relay database returned no data.");
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
    const row = {
      owner_id: ownerId,
      idempotency_key: idempotencyKey,
      title: input.title,
      description: input.description,
      project_name: input.projectName,
      priority: input.priority,
      due_at: input.dueAt,
    };
    const data = this.unwrap(await this.client.from("capture_queue")
      .upsert(row, { onConflict: "owner_id,idempotency_key", ignoreDuplicates: false })
      .select("id,idempotency_key,title,description,project_name,priority,due_at,status,created_at,updated_at")
      .single());
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
    const row = {
      owner_id: ownerId,
      idempotency_key: idempotencyKey,
      task_id: input.taskId,
      device_id: input.deviceId,
      repository_path: input.repositoryPath,
      instructions: input.instructions,
    };
    const data = this.unwrap(await this.client.from("execution_queue")
      .upsert(row, { onConflict: "owner_id,idempotency_key", ignoreDuplicates: false })
      .select("id,idempotency_key,task_id,device_id,repository_path,instructions,status,local_run_id,result_summary,created_at,updated_at")
      .single());
    return camelize(record(data, "execution"));
  }

  async getExecution(ownerId: string, executionId: string): Promise<JsonObject | null> {
    const { data, error } = await this.client.from("execution_queue")
      .select("id,task_id,device_id,status,local_run_id,result_summary,created_at,updated_at")
      .eq("owner_id", ownerId)
      .eq("id", executionId)
      .maybeSingle();
    if (error) throw new Error(error.message);
    return data ? camelize(data as JsonObject) : null;
  }

  async pull(ownerId: string, deviceId: string): Promise<JsonObject> {
    const now = new Date();
    const leaseExpiresAt = new Date(now.getTime() + 60_000).toISOString();
    const reclaimBefore = now.toISOString();
    const captureCandidates = this.unwrap(await this.client.from("capture_queue")
      .select("id,idempotency_key,title,description,project_name,priority,due_at,status")
      .eq("owner_id", ownerId)
      .or(`status.eq.queued,and(status.eq.claimed,lease_expires_at.lt.${reclaimBefore})`)
      .order("created_at", { ascending: true })
      .limit(20));
    const executionCandidates = this.unwrap(await this.client.from("execution_queue")
      .select("id,idempotency_key,task_id,device_id,repository_path,instructions,status")
      .eq("owner_id", ownerId)
      .eq("device_id", deviceId)
      .or(`status.eq.queued,and(status.eq.claimed,lease_expires_at.lt.${reclaimBefore})`)
      .order("created_at", { ascending: true })
      .limit(10));

    const captures: JsonObject[] = [];
    for (const candidate of captureCandidates as JsonObject[]) {
      const { data, error } = await this.client.from("capture_queue")
        .update({ status: "claimed", claimed_by: deviceId, lease_expires_at: leaseExpiresAt, updated_at: now.toISOString() })
        .eq("owner_id", ownerId)
        .eq("id", candidate.id)
        .in("status", ["queued", "claimed"])
        .select("id,idempotency_key,title,description,project_name,priority,due_at,status")
        .maybeSingle();
      if (error) throw new Error(error.message);
      if (data) captures.push(camelize(data as JsonObject));
    }

    const executions: JsonObject[] = [];
    for (const candidate of executionCandidates as JsonObject[]) {
      const { data, error } = await this.client.from("execution_queue")
        .update({ status: "claimed", claimed_by: deviceId, lease_expires_at: leaseExpiresAt, updated_at: now.toISOString() })
        .eq("owner_id", ownerId)
        .eq("id", candidate.id)
        .in("status", ["queued", "claimed"])
        .select("id,idempotency_key,task_id,device_id,repository_path,instructions,status")
        .maybeSingle();
      if (error) throw new Error(error.message);
      if (data) executions.push(camelize(data as JsonObject));
    }
    return { deviceId, leaseExpiresAt, captures, executions };
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
      const { error } = await this.client.from("capture_queue")
        .update({ status: "delivered", delivered_task_id: deliveredTaskId, delivered_at: now, updated_at: now, lease_expires_at: null })
        .eq("owner_id", ownerId).eq("id", captureId).eq("claimed_by", deviceId);
      if (error) throw new Error(error.message);
    }
    for (const update of records(payload.executionUpdates)) {
      const executionId = text(update.executionId, "executionUpdate.executionId");
      const nextStatus = text(update.status, "executionUpdate.status");
      const current = await this.getExecution(ownerId, executionId);
      if (!current || !canTransitionExecution(String(current.status), nextStatus)) {
        throw new Error(`Execution ${executionId} cannot transition to ${nextStatus}.`);
      }
      const { error } = await this.client.from("execution_queue").update({
        status: nextStatus,
        local_run_id: update.localRunId ?? current.localRunId ?? null,
        result_summary: update.resultSummary ?? current.resultSummary ?? null,
        updated_at: now,
        lease_expires_at: nextStatus === "claimed" ? current.leaseExpiresAt ?? null : null,
      }).eq("owner_id", ownerId).eq("id", executionId).eq("device_id", deviceId);
      if (error) throw new Error(error.message);
    }
    return { accepted: true, acceptedAt: now };
  }
}
