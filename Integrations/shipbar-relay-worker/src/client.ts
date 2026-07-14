import { execFile } from "node:child_process";
import type {
  CloudCapture,
  CloudCommand,
  CloudExecution,
  PullResult,
  PushPayload,
  RelayPort,
  RunSummary,
  CommandResult,
  ShipBarPort,
  TaskSummary,
  ProductivitySnapshot,
} from "./worker.js";

type JsonObject = Record<string, unknown>;

function object(value: unknown, name: string): JsonObject {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error(`${name} was not an object.`);
  return value as JsonObject;
}

export class RelayClient implements RelayPort {
  constructor(private readonly url: string, private readonly key: string) {}

  private async request(path: string, body: JsonObject): Promise<JsonObject> {
    const response = await fetch(`${this.url.replace(/\/$/, "")}${path}`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-ShipBar-Key": this.key },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(20_000),
    });
    const payload = object(await response.json(), "Relay response");
    if (!response.ok) throw new Error(`ShipBar relay ${response.status}: ${String(payload.message ?? "request failed")}`);
    return payload;
  }

  async pull(deviceId: string): Promise<PullResult> {
    const payload = await this.request("/sync/pull", { deviceId });
    return {
      captures: Array.isArray(payload.captures) ? payload.captures as CloudCapture[] : [],
      executions: Array.isArray(payload.executions) ? payload.executions as CloudExecution[] : [],
      commands: Array.isArray(payload.commands) ? payload.commands as CloudCommand[] : [],
    };
  }

  push(payload: PushPayload): Promise<JsonObject> {
    return this.request("/sync/push", payload);
  }
}

type BridgeEnvelope = { result?: JsonObject; errorMessage?: string };

export class ShipBarClient implements ShipBarPort {
  constructor(
    private readonly binaryPath = "/Applications/ShipBar.app/Contents/Helpers/shipbarctl",
    private readonly timeoutMs = 20_000,
  ) {}

  private call(args: string[]): Promise<BridgeEnvelope> {
    return new Promise((resolve, reject) => {
      execFile(this.binaryPath, args, { timeout: this.timeoutMs, maxBuffer: 4_000_000 }, (error, stdout, stderr) => {
        if (error) {
          reject(new Error(`shipbarctl failed: ${stderr.trim() || error.message}`));
          return;
        }
        try {
          const envelope = object(JSON.parse(stdout), "shipbarctl response") as BridgeEnvelope;
          if (envelope.errorMessage) reject(new Error(envelope.errorMessage));
          else resolve(envelope);
        } catch (cause) {
          reject(new Error(`shipbarctl returned invalid JSON: ${cause instanceof Error ? cause.message : String(cause)}`));
        }
      });
    });
  }

  async productivitySnapshot(): Promise<ProductivitySnapshot> {
    const result = object((await this.call(["productivity-snapshot"])).result, "productivity snapshot");
    return {
      tasks: Array.isArray(result.tasks) ? result.tasks as TaskSummary[] : [],
      projects: Array.isArray(result.projects) ? result.projects as ProductivitySnapshot["projects"] : [],
    };
  }

  async queueCapture(capture: CloudCapture): Promise<TaskSummary> {
    const args = ["queue-capture", "--capture", capture.id, "--title", capture.title];
    if (capture.description) args.push("--description", capture.description);
    if (capture.projectName) args.push("--project", capture.projectName);
    if (capture.priority) args.push("--priority", capture.priority);
    if (capture.dueAt) args.push("--due-at", capture.dueAt);
    const result = object((await this.call(args)).result, "queue-capture result");
    const tasks = result.tasks;
    if (!Array.isArray(tasks) || tasks.length !== 1) throw new Error("ShipBar did not return the saved task.");
    return object(tasks[0], "saved task") as TaskSummary;
  }

  async prepareRun(execution: CloudExecution): Promise<RunSummary> {
    if (!execution.repositoryPath) throw new Error("A repository path is required to prepare a run.");
    const args = ["prepare-run", "--task", execution.taskId, "--repository", execution.repositoryPath];
    args.push("--preparation-key", execution.id);
    if (execution.instructions) args.push("--instructions", execution.instructions);
    const result = object((await this.call(args)).result, "prepare-run result");
    return object(result.run, "prepared run") as RunSummary;
  }

  async runStatus(runId: string): Promise<RunSummary> {
    const result = object((await this.call(["run-status", "--run", runId])).result, "run-status result");
    return object(result.run, "run status") as RunSummary;
  }

  async applyCommand(command: CloudCommand): Promise<CommandResult> {
    try {
      const envelope = await this.call([
        "apply-command",
        "--command-id", command.id,
        "--command", JSON.stringify(command.payload),
      ]);
      const result = object(envelope.result, "apply-command result");
      return object(result.commandResult, "command result") as CommandResult;
    } catch (cause) {
      const summary = cause instanceof Error ? cause.message : "ShipBar could not apply the command.";
      return {
        commandID: command.id,
        status: summary.toLowerCase().includes("conflict") ? "conflicted" : "failed",
        summary,
      };
    }
  }
}
