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

function fixture(pull: Record<string, unknown> = { captures: [], executions: [] }) {
  const relay: RelayPort = {
    pull: vi.fn().mockResolvedValue(pull),
    push: vi.fn().mockResolvedValue({ accepted: true }),
  };
  const shipbar: ShipBarPort = {
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
  };
  const worker = new RelayWorker({
    relay,
    shipbar,
    device: { id: "mac-1", name: "Tadies Mac", platform: "macos" },
  });
  return { relay, shipbar, worker };
}

describe("RelayWorker", () => {
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
});
