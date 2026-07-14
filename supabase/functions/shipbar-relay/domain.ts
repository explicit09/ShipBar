export type CaptureInput = {
  title: string;
  description: string;
  projectName: string | null;
  priority: "low" | "normal" | "high" | "urgent";
  dueAt: string | null;
};

export type ExecutionInput = {
  taskId: string;
  deviceId: string;
  repositoryPath: string | null;
  instructions: string;
};

function hex(bytes: Uint8Array): string {
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

export async function hashRelayKey(key: string): Promise<string> {
  if (key.length < 32) throw new Error("Relay key must be at least 32 characters.");
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(key));
  return hex(new Uint8Array(digest));
}

function secureEqual(left: string, right: string): boolean {
  const a = new TextEncoder().encode(left);
  const b = new TextEncoder().encode(right);
  let mismatch = a.length ^ b.length;
  const length = Math.max(a.length, b.length);
  for (let index = 0; index < length; index += 1) {
    mismatch |= (a[index] ?? 0) ^ (b[index] ?? 0);
  }
  return mismatch === 0;
}

export async function isAuthorized(key: string | null, expectedHash: string): Promise<boolean> {
  if (!key || !expectedHash) return false;
  try {
    return secureEqual(await hashRelayKey(key), expectedHash.toLowerCase());
  } catch {
    return false;
  }
}

export function isDeviceOnline(lastSeenAt: string, now: Date = new Date()): boolean {
  const timestamp = Date.parse(lastSeenAt);
  if (!Number.isFinite(timestamp)) return false;
  const age = now.getTime() - timestamp;
  return age >= 0 && age <= 90_000;
}

const executionTransitions: Record<string, ReadonlySet<string>> = {
  queued: new Set(["claimed", "canceled"]),
  claimed: new Set(["running", "failed", "canceled"]),
  running: new Set(["needs_review", "completed", "failed", "canceled"]),
  needs_review: new Set(["running", "completed", "failed", "canceled"]),
  completed: new Set(),
  failed: new Set(),
  canceled: new Set(),
};

export function canTransitionExecution(from: string, to: string): boolean {
  return executionTransitions[from]?.has(to) ?? false;
}

function object(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Request body must be a JSON object.");
  }
  return value as Record<string, unknown>;
}

function requiredText(value: unknown, name: string, maxLength: number): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new Error(`${name} is required.`);
  }
  const result = value.trim();
  if (result.length > maxLength) throw new Error(`${name} is too long.`);
  return result;
}

function optionalText(value: unknown, name: string, maxLength: number): string | null {
  if (value === undefined || value === null || value === "") return null;
  return requiredText(value, name, maxLength);
}

function optionalDate(value: unknown, name: string): string | null {
  const text = optionalText(value, name, 64);
  if (!text) return null;
  const date = new Date(text);
  if (!Number.isFinite(date.getTime())) throw new Error(`${name} must be an ISO date.`);
  return date.toISOString();
}

export function parseCapture(value: unknown): CaptureInput {
  const input = object(value);
  const priority = input.priority ?? "normal";
  if (!["low", "normal", "high", "urgent"].includes(String(priority))) {
    throw new Error("priority must be low, normal, high, or urgent.");
  }
  return {
    title: requiredText(input.title, "title", 300),
    description: optionalText(input.description, "description", 20_000) ?? "",
    projectName: optionalText(input.projectName, "projectName", 200),
    priority: priority as CaptureInput["priority"],
    dueAt: optionalDate(input.dueAt, "dueAt"),
  };
}

export function parseExecution(value: unknown): ExecutionInput {
  const input = object(value);
  return {
    taskId: requiredText(input.taskId, "taskId", 200),
    deviceId: requiredText(input.deviceId, "deviceId", 200),
    repositoryPath: optionalText(input.repositoryPath, "repositoryPath", 2_000),
    instructions: optionalText(input.instructions, "instructions", 20_000) ?? "",
  };
}
