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

export type CloudCommand = {
  id: string;
  kind: string;
  status: string;
  payload: Record<string, unknown>;
};

export type TaskSummary = {
  taskID: string;
  title: string;
  taskDescription: string;
  prompt?: string;
  status: string;
  priority: string;
  type: string;
  projectName: string | null;
  dueDate: string | null;
  focusDate: string | null;
  focusOrder: number | null;
  isInbox: boolean;
  updatedAt: string;
  revision?: number;
  trashedAt?: string | null;
  sourceApp?: string;
  sourceURL?: string;
};

export type ProjectSummary = {
  projectID: string;
  name: string;
  outcome: string;
  basePrompt: string;
  repoPath: string;
  color: string;
  icon: string;
  sortOrder: number;
  updatedAt: string;
  revision: number;
  trashedAt: string | null;
};

export type ProductivitySnapshot = { tasks: TaskSummary[]; projects: ProjectSummary[] };

export type CommandResult = {
  commandID: string;
  status: "applied" | "failed" | "conflicted";
  summary: string;
  task?: TaskSummary;
  project?: ProjectSummary;
  deletedRecordID?: string;
  deletedRecordType?: "task" | "project";
};

export type RunSummary = {
  runID: string;
  status: string;
  resultSummary?: string | null;
};

export type PullResult = {
  captures: CloudCapture[];
  executions: CloudExecution[];
  commands: CloudCommand[];
};

export type PushPayload = Record<string, unknown> & { deviceId: string };

export interface RelayPort {
  pull(deviceId: string): Promise<PullResult>;
  push(payload: PushPayload): Promise<Record<string, unknown>>;
}

export interface ShipBarPort {
  productivitySnapshot(): Promise<ProductivitySnapshot>;
  queueCapture(capture: CloudCapture): Promise<TaskSummary>;
  prepareRun(execution: CloudExecution): Promise<RunSummary>;
  runStatus(runId: string): Promise<RunSummary>;
  applyCommand(command: CloudCommand): Promise<CommandResult>;
}

export type WorkerDevice = { id: string; name: string; platform: string };

function taskMirror(task: TaskSummary): Record<string, unknown> {
  return {
    taskId: task.taskID,
    title: task.title,
    description: task.taskDescription,
    prompt: task.prompt ?? "",
    status: task.status,
    priority: task.priority,
    type: task.type,
    projectName: task.projectName,
    dueAt: task.dueDate,
    focusDate: task.focusDate?.slice(0, 10) ?? null,
    focusOrder: task.focusOrder,
    isInbox: task.isInbox,
    updatedAt: task.updatedAt,
    revision: task.revision ?? 0,
    trashedAt: task.trashedAt ?? null,
    sourceApp: task.sourceApp ?? "",
    sourceUrl: task.sourceURL ?? "",
  };
}

function projectMirror(project: ProjectSummary): Record<string, unknown> {
  return {
    projectId: project.projectID,
    name: project.name,
    outcome: project.outcome,
    basePrompt: project.basePrompt,
    repoPath: project.repoPath,
    color: project.color,
    icon: project.icon,
    sortOrder: project.sortOrder,
    updatedAt: project.updatedAt,
    revision: project.revision,
    trashedAt: project.trashedAt,
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
  private activeCycle: Promise<{ captures: number; executions: number; commands: number }> | null = null;

  constructor(options: { relay: RelayPort; shipbar: ShipBarPort; device: WorkerDevice }) {
    this.relay = options.relay;
    this.shipbar = options.shipbar;
    this.device = options.device;
  }

  async cycle(): Promise<{ captures: number; executions: number; commands: number }> {
    if (this.activeCycle) return this.activeCycle;
    const cycle = this.runCycle();
    this.activeCycle = cycle;
    try {
      return await cycle;
    } finally {
      if (this.activeCycle === cycle) this.activeCycle = null;
    }
  }

  private async runCycle(): Promise<{ captures: number; executions: number; commands: number }> {
    const snapshot = await this.shipbar.productivitySnapshot();
    await this.relay.push({
      deviceId: this.device.id,
      taskMirrors: snapshot.tasks.map(taskMirror),
      projectMirrors: snapshot.projects.map(projectMirror),
      heartbeat: {
        name: this.device.name,
        platform: this.device.platform,
        capabilities: ["capture", "productivity-commands", "codex-execution"],
      },
    });

    const pulled = await this.relay.pull(this.device.id);
    const captureAcknowledgements: Record<string, unknown>[] = [];
    const taskMirrors: Record<string, unknown>[] = [];
    const executionUpdates: Record<string, unknown>[] = [];
    const commandAcknowledgements: Record<string, unknown>[] = [];
    const projectMirrors: Record<string, unknown>[] = [];
    const taskTombstones: string[] = [];
    const projectTombstones: string[] = [];

    for (const capture of pulled.captures) {
      const saved = await this.shipbar.queueCapture(capture);
      captureAcknowledgements.push({ captureId: capture.id, taskId: saved.taskID });
      taskMirrors.push(taskMirror(saved));
    }

    for (const command of pulled.commands ?? []) {
      const applied = await this.shipbar.applyCommand(command);
      const result: Record<string, unknown> = {};
      if (applied.task) {
        result.task = applied.task;
        taskMirrors.push(taskMirror(applied.task));
      }
      if (applied.project) {
        result.project = applied.project;
        projectMirrors.push(projectMirror(applied.project));
      }
      if (applied.deletedRecordID && applied.deletedRecordType === "task") {
        taskTombstones.push(applied.deletedRecordID);
        result.deletedRecordID = applied.deletedRecordID;
        result.deletedRecordType = applied.deletedRecordType;
      }
      if (applied.deletedRecordID && applied.deletedRecordType === "project") {
        projectTombstones.push(applied.deletedRecordID);
        result.deletedRecordID = applied.deletedRecordID;
        result.deletedRecordType = applied.deletedRecordType;
      }
      commandAcknowledgements.push({
        commandId: command.id,
        status: applied.status,
        summary: applied.summary,
        result,
      });
    }

    if (commandAcknowledgements.length > 0) {
      await this.relay.push({
        deviceId: this.device.id,
        taskMirrors,
        commandAcknowledgements,
        projectMirrors,
        taskTombstones,
        projectTombstones,
      });
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
      let run: RunSummary;
      if (execution.localRunId) {
        try {
          run = await this.shipbar.runStatus(execution.localRunId);
        } catch (cause) {
          executionUpdates.push({
            executionId: execution.id,
            expectedStatus: execution.status,
            status: "failed",
            localRunId: execution.localRunId,
            resultSummary: cause instanceof Error ? cause.message : "The local ShipBar run is unavailable.",
          });
          continue;
        }
      } else {
        run = await this.shipbar.prepareRun(execution);
      }
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
    return {
      captures: captureAcknowledgements.length,
      executions: executionUpdates.length,
      commands: commandAcknowledgements.length,
    };
  }
}
