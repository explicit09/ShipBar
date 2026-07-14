export type CloudCapture = {
  id: string;
  title: string;
  description: string;
  projectName: string | null;
  priority: string;
  dueAt: string | null;
};

export type CloudExecution = {
  id: string;
  taskId: string;
  deviceId: string;
  repositoryPath: string | null;
  instructions: string;
  status: string;
  localRunId: string | null;
};

export type TaskSummary = {
  taskID: string;
  title: string;
  taskDescription: string;
  status: string;
  priority: string;
  type: string;
  projectName: string | null;
  dueDate: string | null;
  focusDate: string | null;
  focusOrder: number | null;
  isInbox: boolean;
  updatedAt: string;
};

export type RunSummary = {
  runID: string;
  status: string;
  resultSummary?: string | null;
};

export type PullResult = {
  captures: CloudCapture[];
  executions: CloudExecution[];
};

export type PushPayload = Record<string, unknown> & { deviceId: string };

export interface RelayPort {
  pull(deviceId: string): Promise<PullResult>;
  push(payload: PushPayload): Promise<Record<string, unknown>>;
}

export interface ShipBarPort {
  queueCapture(capture: CloudCapture): Promise<TaskSummary>;
  prepareRun(execution: CloudExecution): Promise<RunSummary>;
  runStatus(runId: string): Promise<RunSummary>;
}

export type WorkerDevice = { id: string; name: string; platform: string };

function taskMirror(task: TaskSummary): Record<string, unknown> {
  return {
    taskId: task.taskID,
    title: task.title,
    description: task.taskDescription,
    status: task.status,
    priority: task.priority,
    projectName: task.projectName,
    dueAt: task.dueDate,
    focusDate: task.focusDate?.slice(0, 10) ?? null,
    focusOrder: task.focusOrder,
    isInbox: task.isInbox,
    updatedAt: task.updatedAt,
  };
}

function cloudStatus(localStatus: string): string {
  const statuses: Record<string, string> = {
    prepared: "claimed",
    handedOff: "claimed",
    running: "running",
    needsReview: "needs_review",
    completed: "completed",
    failed: "failed",
    canceled: "canceled",
  };
  const status = statuses[localStatus];
  if (!status) throw new Error(`ShipBar returned unsupported run status '${localStatus}'.`);
  return status;
}

export class RelayWorker {
  private readonly relay: RelayPort;
  private readonly shipbar: ShipBarPort;
  private readonly device: WorkerDevice;
  private activeCycle: Promise<{ captures: number; executions: number }> | null = null;

  constructor(options: { relay: RelayPort; shipbar: ShipBarPort; device: WorkerDevice }) {
    this.relay = options.relay;
    this.shipbar = options.shipbar;
    this.device = options.device;
  }

  async cycle(): Promise<{ captures: number; executions: number }> {
    if (this.activeCycle) return this.activeCycle;
    const cycle = this.runCycle();
    this.activeCycle = cycle;
    try {
      return await cycle;
    } finally {
      if (this.activeCycle === cycle) this.activeCycle = null;
    }
  }

  private async runCycle(): Promise<{ captures: number; executions: number }> {
    await this.relay.push({
      deviceId: this.device.id,
      heartbeat: {
        name: this.device.name,
        platform: this.device.platform,
        capabilities: ["capture", "codex-execution"],
      },
    });

    const pulled = await this.relay.pull(this.device.id);
    const captureAcknowledgements: Record<string, unknown>[] = [];
    const taskMirrors: Record<string, unknown>[] = [];
    const executionUpdates: Record<string, unknown>[] = [];

    for (const capture of pulled.captures) {
      const saved = await this.shipbar.queueCapture(capture);
      captureAcknowledgements.push({ captureId: capture.id, taskId: saved.taskID });
      taskMirrors.push(taskMirror(saved));
    }

    for (const execution of pulled.executions) {
      if (execution.deviceId !== this.device.id) continue;
      if (!execution.localRunId && !execution.repositoryPath) {
        executionUpdates.push({
          executionId: execution.id,
          expectedStatus: execution.status,
          status: "failed",
          resultSummary: "A repository path is required before ShipBar can prepare this run.",
        });
        continue;
      }
      const run = execution.localRunId
        ? await this.shipbar.runStatus(execution.localRunId)
        : await this.shipbar.prepareRun(execution);
      executionUpdates.push({
        executionId: execution.id,
        expectedStatus: execution.status,
        status: cloudStatus(run.status),
        localRunId: run.runID,
        resultSummary: run.resultSummary ?? null,
      });
    }

    if (captureAcknowledgements.length > 0 || executionUpdates.length > 0) {
      await this.relay.push({
        deviceId: this.device.id,
        captureAcknowledgements,
        taskMirrors,
        executionUpdates,
      });
    }
    return { captures: captureAcknowledgements.length, executions: executionUpdates.length };
  }
}
