import { describe, expect, it, vi } from "vitest";
import { RelayWorker, type RelayPort, type ShipBarPort } from "../src/worker.js";

const capture = {
  id: "capture-1",
  title: "Write report",
  description: "Include verified results",
  projectName: null,
  priority: "high",
  dueAt: null,
};

function fixture(pull: Record<string, unknown> = { captures: [], executions: [], commands: [] }) {
  const relay: RelayPort = {
    pull: vi.fn().mockResolvedValue(pull),
    push: vi.fn().mockResolvedValue({ accepted: true }),
  };
  const shipbar: ShipBarPort = {
    productivitySnapshot: vi.fn().mockResolvedValue({ tasks: [], projects: [] }),
    queueCapture: vi.fn().mockResolvedValue({
      taskID: "task-1",
      title: "Write report",
      taskDescription: "Include verified results",
      status: "open",
      priority: "high",
      type: "action",
      projectName: null,
      dueDate: null,
      focusDate: null,
      focusOrder: null,
      isInbox: true,
      updatedAt: "2026-07-13T12:00:00.000Z",
    }),
    prepareRun: vi.fn().mockResolvedValue({ runID: "run-1", status: "prepared" }),
    runStatus: vi.fn().mockResolvedValue({ runID: "run-1", status: "running" }),
    applyCommand: vi.fn().mockResolvedValue({
      commandID: "command-1",
      status: "applied",
      summary: "Created project ChatGPT QA.",
      project: {
        projectID: "project-1", name: "ChatGPT QA", outcome: "Verify parity",
        basePrompt: "Keep evidence", repoPath: "/tmp/repo", color: "purple",
        icon: "checkmark.seal", sortOrder: 0, revision: 1, trashedAt: null,
        updatedAt: "2026-07-14T12:00:00.000Z",
      },
    }),
  };
  const worker = new RelayWorker({
    relay,
    shipbar,
    device: { id: "mac-1", name: "Tadies Mac", platform: "macos" },
  });
  return { relay, shipbar, worker };
}

describe("RelayWorker", () => {
  it("publishes the complete local productivity snapshot before pulling commands", async () => {
    const { relay, shipbar, worker } = fixture();
    vi.mocked(shipbar.productivitySnapshot).mockResolvedValue({
      tasks: [{
        taskID: "existing-task", title: "Existing task", taskDescription: "Local details",
        prompt: "Do it carefully", status: "todo", priority: "normal", type: "action",
        projectName: null, dueDate: null, focusDate: null, focusOrder: null, isInbox: true,
        updatedAt: "2026-07-14T12:00:00.000Z", revision: 3, trashedAt: null,
      }],
      projects: [{
        projectID: "existing-project", name: "Existing project", outcome: "Ship it",
        basePrompt: "Use evidence", repoPath: "/tmp/project", color: "blue", icon: "folder",
        sortOrder: 2, updatedAt: "2026-07-14T12:00:00.000Z", revision: 4, trashedAt: null,
      }],
    });

    await worker.cycle();

    expect(vi.mocked(relay.push).mock.calls[0]?.[0]).toMatchObject({
      taskMirrors: [{ taskId: "existing-task", title: "Existing task", revision: 3 }],
      projectMirrors: [{ projectId: "existing-project", name: "Existing project", revision: 4 }],
    });
    expect(relay.pull).toHaveBeenCalledAfter(vi.mocked(relay.push));
  });
  it("retains cloud work when pull is offline and sends no acknowledgement", async () => {
    const { relay, shipbar, worker } = fixture();
    vi.mocked(relay.pull).mockRejectedValue(new Error("offline"));

    await expect(worker.cycle()).rejects.toThrow("offline");

    expect(shipbar.queueCapture).not.toHaveBeenCalled();
    expect(relay.push).toHaveBeenCalledTimes(1);
    expect(vi.mocked(relay.push).mock.calls[0]?.[0]).not.toHaveProperty("captureAcknowledgements");
  });

  it("acknowledges a capture only after ShipBar returns its saved task", async () => {
    const { relay, shipbar, worker } = fixture({ captures: [capture], executions: [] });

    await worker.cycle();

    expect(shipbar.queueCapture).toHaveBeenCalledWith(capture);
    expect(relay.push).toHaveBeenCalledTimes(2);
    expect(vi.mocked(relay.push).mock.calls[1]?.[0]).toMatchObject({
      deviceId: "mac-1",
      captureAcknowledgements: [{ captureId: "capture-1", taskId: "task-1" }],
      taskMirrors: [{ taskId: "task-1", title: "Write report" }],
    });
  });

  it("does not acknowledge any capture when the local save fails", async () => {
    const { relay, shipbar, worker } = fixture({ captures: [capture], executions: [] });
    vi.mocked(shipbar.queueCapture).mockRejectedValue(new Error("ShipBar closed"));

    await expect(worker.cycle()).rejects.toThrow("ShipBar closed");

    expect(relay.push).toHaveBeenCalledTimes(1);
  });

  it("safely redelivers duplicate captures using the cloud capture ID", async () => {
    const { relay, shipbar, worker } = fixture({ captures: [capture], executions: [] });

    await worker.cycle();
    await worker.cycle();

    expect(shipbar.queueCapture).toHaveBeenCalledTimes(2);
    expect(shipbar.queueCapture).toHaveBeenNthCalledWith(1, capture);
    expect(shipbar.queueCapture).toHaveBeenNthCalledWith(2, capture);
    const acknowledgements = vi.mocked(relay.push).mock.calls
      .map(([payload]) => payload.captureAcknowledgements)
      .filter(Boolean);
    expect(acknowledgements).toEqual([
      [{ captureId: "capture-1", taskId: "task-1" }],
      [{ captureId: "capture-1", taskId: "task-1" }],
    ]);
  });

  it("prepares an execution for the matching device without inventing running state", async () => {
    const execution = {
      id: "execution-1",
      taskId: "task-1",
      deviceId: "mac-1",
      repositoryPath: "/tmp/repo",
      instructions: "Run focused tests",
      status: "claimed",
      localRunId: null,
    };
    const { relay, shipbar, worker } = fixture({ captures: [], executions: [execution] });

    await worker.cycle();

    expect(shipbar.prepareRun).toHaveBeenCalledWith(execution);
    expect(vi.mocked(relay.push).mock.calls[1]?.[0]).toMatchObject({
      executionUpdates: [{ executionId: "execution-1", status: "claimed", localRunId: "run-1" }],
    });
  });

  it("applies a productivity command and acknowledges its project mirror", async () => {
    const command = {
      id: "command-1", kind: "createProject", status: "claimed",
      payload: { kind: "createProject", project: { name: "ChatGPT QA" } },
    };
    const { relay, shipbar, worker } = fixture({ captures: [], executions: [], commands: [command] });

    await worker.cycle();

    expect(shipbar.applyCommand).toHaveBeenCalledWith(command);
    expect(vi.mocked(relay.push).mock.calls[1]?.[0]).toMatchObject({
      deviceId: "mac-1",
      commandAcknowledgements: [{
        commandId: "command-1", status: "applied", summary: "Created project ChatGPT QA.",
      }],
      projectMirrors: [{ projectId: "project-1", name: "ChatGPT QA", revision: 1 }],
    });
  });

  it("acknowledges command conflicts truthfully without aborting the cycle", async () => {
    const command = {
      id: "command-conflict", kind: "updateTask", status: "claimed",
      payload: { kind: "updateTask", recordID: "task-1", expectedRevision: 1 },
    };
    const { relay, shipbar, worker } = fixture({ captures: [], executions: [], commands: [command] });
    vi.mocked(shipbar.applyCommand).mockResolvedValue({
      commandID: "command-conflict", status: "conflicted",
      summary: "Task revision conflict; refresh before retrying.",
    });

    await worker.cycle();

    expect(vi.mocked(relay.push).mock.calls[1]?.[0]).toMatchObject({
      commandAcknowledgements: [{ commandId: "command-conflict", status: "conflicted" }],
    });
  });

  it("publishes a tombstone after permanent deletion so stale mirrors disappear", async () => {
    const command = {
      id: "command-delete", kind: "permanentlyDeleteTask", status: "claimed",
      payload: { kind: "permanentlyDeleteTask", recordID: "task-1", expectedRevision: 7 },
    };
    const { relay, shipbar, worker } = fixture({ captures: [], executions: [], commands: [command] });
    vi.mocked(shipbar.applyCommand).mockResolvedValue({
      commandID: "command-delete", status: "applied", summary: "Permanently deleted task.",
      deletedRecordID: "task-1", deletedRecordType: "task",
    });

    await worker.cycle();

    expect(vi.mocked(relay.push).mock.calls[1]?.[0]).toMatchObject({
      taskTombstones: ["task-1"],
      commandAcknowledgements: [{ commandId: "command-delete", status: "applied" }],
    });
  });

  it("syncs an existing local run status instead of preparing a duplicate", async () => {
    const execution = {
      id: "execution-1",
      taskId: "task-1",
      deviceId: "mac-1",
      repositoryPath: "/tmp/repo",
      instructions: "",
      status: "claimed",
      localRunId: "run-1",
    };
    const { relay, shipbar, worker } = fixture({ captures: [], executions: [execution] });

    await worker.cycle();

    expect(shipbar.prepareRun).not.toHaveBeenCalled();
    expect(shipbar.runStatus).toHaveBeenCalledWith("run-1");
    expect(vi.mocked(relay.push).mock.calls[1]?.[0]).toMatchObject({
      executionUpdates: [{ executionId: "execution-1", status: "running", localRunId: "run-1" }],
    });
  });

  it("retries a failed cloud push using the same relay preparation identity", async () => {
    const execution = {
      id: "execution-retry",
      taskId: "task-1",
      deviceId: "mac-1",
      repositoryPath: "/tmp/repo",
      instructions: "",
      status: "claimed",
      localRunId: null,
    };
    const { relay, shipbar, worker } = fixture({ captures: [], executions: [execution] });
    vi.mocked(relay.push)
      .mockResolvedValueOnce({ accepted: true })
      .mockRejectedValueOnce(new Error("cloud unavailable"))
      .mockResolvedValue({ accepted: true });

    await expect(worker.cycle()).rejects.toThrow("cloud unavailable");
    await worker.cycle();

    expect(shipbar.prepareRun).toHaveBeenCalledTimes(2);
    expect(shipbar.prepareRun).toHaveBeenNthCalledWith(1, execution);
    expect(shipbar.prepareRun).toHaveBeenNthCalledWith(2, execution);
    const successfulUpdate = vi.mocked(relay.push).mock.calls.at(-1)?.[0].executionUpdates;
    expect(successfulUpdate).toEqual([expect.objectContaining({
      executionId: "execution-retry", localRunId: "run-1",
    })]);
  });

  it("coalesces overlapping interval cycles into one worker pass", async () => {
    const { relay, worker } = fixture();
    let release!: () => void;
    vi.mocked(relay.pull).mockImplementation(() => new Promise((resolve) => {
      release = () => resolve({ captures: [], executions: [] });
    }));

    const first = worker.cycle();
    const second = worker.cycle();
    await vi.waitFor(() => expect(relay.pull).toHaveBeenCalledTimes(1));
    release();
    await Promise.all([first, second]);

    expect(relay.pull).toHaveBeenCalledTimes(1);
    expect(relay.push).toHaveBeenCalledTimes(1);
  });
});
