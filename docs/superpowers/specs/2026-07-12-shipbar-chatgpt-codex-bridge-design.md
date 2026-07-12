# ShipBar ChatGPT and Codex Bridge Design

## Product Goal

Connect ShipBar to ChatGPT and Codex without duplicating ShipBar's storage, paying for unnecessary model API calls, or inventing a second remote-device system.

The product has two distinct lanes:

1. **Capture and enrichment:** ChatGPT turns a phone conversation into a detailed ShipBar task.
2. **Coding execution:** Codex Remote runs an approved prepared task on a selected connected host and returns truthful status and evidence to ShipBar.

## Platform Boundary

The owner uses ChatGPT Personal Pro. At the time of this design, custom MCP write actions are not generally available to Personal Pro, while Codex Remote is available through the ChatGPT plan. Therefore:

- Phone writes use the native Share Extension and App Intents.
- ChatGPT may read/search through a remote MCP connection when its host is reachable.
- Codex execution uses the official Codex Remote host picker and pairing.
- A write-capable MCP adapter is implemented behind a capability flag but is not presented as active until OpenAI enables the required Personal Pro surface.

## System Shape

```text
ChatGPT mobile conversation
        |
        | Share / App Intent
        v
ShipBar iPhone capture queue -----> private CloudKit -----> ShipBar Mac
                                                             |
                                                             | prepared run
                                                             v
ChatGPT mobile -> Codex Remote host selection -> Codex + ShipBar plugin
                                                             |
                                                             v
                                                status, summary, evidence
                                                             |
                                                             v
                                                        private CloudKit
```

No ShipBar-hosted model call is required to enrich a capture. ChatGPT performs the language work inside the user's ChatGPT session; ShipBar receives structured text.

## Subproject 1: Reliable Capture and Sync Foundation

### Queue contract

Extend `SharedCapturePayload` into a durable envelope with:

- immutable capture UUID;
- creation date and source metadata;
- import state: `queued`, `imported`, `syncing`, `synced`, or `failed`;
- attempt count, last-attempt date, and user-readable error;
- schema version for forward compatibility.

The Share Extension writes atomically to the App Group while the main iPhone app is closed. Import is idempotent by capture UUID. Consuming the queue never deletes an item before the corresponding ShipTask save succeeds.

### Sync lifecycle

Both Apple apps run a shared `ShipBarSyncCoordinator`:

- at launch;
- whenever the scene becomes active;
- immediately after importing or modifying a task/run;
- on explicit user refresh;
- after a retryable failure using bounded backoff.

Only one direct sync may be active per process. A pending request coalesces into one follow-up pass. The UI displays last successful sync, active syncing, queued changes, and actionable failure details.

### Truth boundary

`Queued` means durable on the current device, not uploaded. `Synced` is shown only after CloudKit success. Duplicate imports and last-write conflicts must not create duplicate tasks.

## Subproject 2: Phone Capture Experience

### Structured capture format

ChatGPT produces a human-readable format that remains useful if parsing fails:

```text
# ShipBar Task
Title: Improve onboarding completion
Project: ShipBar V2
Priority: High
Type: Feature

Description:
Clarify the first-run path and remove unnecessary choices.

Acceptance Criteria:
- A new user reaches the Flight Plan without setup confusion.
- Existing users keep their current data.

Agent Prompt:
Inspect the current onboarding flow, implement the approved design, and attach test evidence.
```

The parser supports missing optional fields, preserves the raw input, rejects an empty title, and never invents an unknown project assignment.

### Share Extension

Replace the immediate auto-dismiss with a compact review sheet showing title, project, priority, and whether an agent prompt was detected. The user can save to Inbox or cancel. Saving writes to the durable queue and reports `Queued for ShipBar` rather than claiming CloudKit sync.

### App Intents

Add intents for:

- `Capture in ShipBar` with text and optional source URL;
- `Show ShipBar Inbox`;
- `Show Today's Flight Plan`;
- `Prepare Task for Codex` when a task identifier is provided.

These enable Shortcuts, Siri, the Action button, and future system integrations. All write intents use the same capture queue and parser as the Share Extension.

## Subproject 3: Codex Execution Bridge and Plugin

### Local bridge

ShipBar exposes the smallest local command surface needed by Codex:

- list prepared runs;
- read a run's frozen task/project/prompt/repository context;
- claim a prepared run;
- mark it running;
- request review with result summary and evidence paths;
- mark failed or canceled with an actionable reason.

The bridge is local-only, authenticated to the current user, uses structured JSON, and never accepts arbitrary shell commands. It calls the existing `AgentRunLifecycle`; it does not write status strings directly.

The implementation should prefer a signed ShipBar command helper communicating through an App Group command/response store or another native local IPC mechanism. It must not open a network listener unless a later subproject proves native IPC insufficient.

### Codex plugin

The ShipBar Codex plugin contains:

- a skill for selecting and executing prepared ShipBar runs;
- command/helper integration for the local bridge;
- explicit confirmation before claiming a run;
- repository-path validation before execution;
- lifecycle updates after acceptance, start, review readiness, failure, or cancellation;
- evidence attachment from diffs, test results, screenshots, and review artifacts.

The plugin does not choose a device. ChatGPT/Codex Remote provides the paired online-host list and the user selects the host. The plugin operates only after that host is active.

### Offline behavior

If no Mac is online, the run remains `Prepared`. When a selected host becomes available, the user can resume through Codex Remote. ShipBar must not claim `Handed off` until the host bridge accepts the run.

## Subproject 4: Personal Pro ChatGPT Surface

### Current surface

Provide a small remote MCP server for supported Personal Pro read/search operations:

- `search_tasks`;
- `get_today`;
- `get_task`;
- `list_prepared_runs`;
- `get_run_status`.

During local-first development, the server may be reached through OpenAI's supported secure tunnel while the Mac is online. Every result is scoped to the authenticated ShipBar user and excludes secrets, API keys, raw filesystem content, and unrelated local data.

### Write readiness

Define but disable write adapters for `create_task`, `update_task`, `complete_task`, and `prepare_run`. Capability discovery must truthfully report that Personal Pro direct writes are unavailable. When OpenAI enables the surface, the same adapters must use ShipBar's queue/lifecycle APIs rather than bypassing them.

Until then, ChatGPT instructs the user to Share the structured capture to ShipBar. It never says a task was saved merely because it generated the text.

## Security and Privacy

- CloudKit private database remains the cross-device source of truth.
- OpenAI API keys remain in Keychain and are never exposed through the bridge or MCP.
- Write actions require explicit user initiation or confirmation.
- Repository access is limited to the task's approved project path.
- Command payloads use UUIDs and idempotency keys.
- Evidence paths are validated before display or upload.
- Logs redact prompt bodies, task descriptions, tokens, and private paths unless the user explicitly opens local diagnostics.

## Delivery Order

1. Verify the current signed iPhone and Mac builds really exchange tasks/runs through CloudKit.
2. Implement the reliable queue and shared sync coordinator.
3. Implement structured capture, Share review, and App Intents.
4. Implement the local execution bridge and Codex plugin.
5. Implement the read/search MCP surface and secure-tunnel development path.
6. Run end-to-end phone-to-Mac-to-Codex-to-phone verification.

Each subproject gets its own implementation plan and review gate. A subproject must be independently usable before the next begins.

## End-to-End Acceptance

1. With both apps closed, sharing a ChatGPT-produced task queues it on iPhone.
2. Opening ShipBar imports exactly one task with the full structured detail.
3. The task appears on Mac after sync with an accurate sync state.
4. Preparing the task creates one `Prepared` run with frozen context.
5. From ChatGPT mobile, the user selects an online Codex Remote host.
6. The plugin confirms the repository and run, then the host accepts it.
7. ShipBar transitions truthfully through `Handed off`, `Running`, and `Needs review`.
8. Summary and evidence appear on both devices after sync.
9. Offline hosts leave the run prepared without data loss or false progress.
10. No ShipBar OpenAI Platform API usage is incurred for ChatGPT phone enrichment.

