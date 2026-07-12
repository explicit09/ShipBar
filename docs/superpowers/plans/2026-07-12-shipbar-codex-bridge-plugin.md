# ShipBar Codex Bridge and Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let Codex safely claim prepared ShipBar work, run it on the user-selected Codex Remote host, and return truthful status and evidence.

**Architecture:** Add a signed local command helper that exchanges versioned request/response envelopes through the ShipBar App Group, have the running menu app process commands through existing lifecycle APIs, and package a Codex plugin that invokes the helper with confirmation and repository validation.

**Tech Stack:** Swift 6 command-line target, App Group IPC, SwiftData, Codex plugin manifest/skills, Swift Testing.

## Global Constraints

- No arbitrary shell command enters ShipBar.
- The helper is local-only and accepts a closed command enum.
- Status mutations use `AgentRunLifecycle`.
- `Handed off` begins only after the host claims the run.
- Repository path and evidence paths are validated.
- Codex Remote owns host pairing and selection.

---

### Task 1: Versioned bridge protocol and store

**Files:**
- Create: `Sources/Shared/Bridge/ShipBarBridgeProtocol.swift`
- Create: `Sources/Shared/Bridge/ShipBarBridgeStore.swift`
- Create: `Tests/ShipBarTests/ShipBarBridgeStoreTests.swift`

**Interfaces:**
- Produces: `ShipBarBridgeCommand`, `ShipBarBridgeRequest`, `ShipBarBridgeResponse`, atomic request/response store.

- [ ] Add failing round-trip, schema rejection, UUID idempotency, timeout, path-validation, and concurrent request tests.
- [ ] Verify RED.
- [ ] Implement closed commands: `listPrepared`, `getContext(runID)`, `claim(runID)`, `markRunning(runID)`, `requestReview(runID,summary,evidencePaths)`, `markFailed(runID,message)`, and `cancel(runID,message)`.
- [ ] Store atomic JSON envelopes under the App Group `Bridge/v1/{requests,responses}` directories; reject unknown schema versions and paths outside approved roots.
- [ ] Run tests; commit `feat: define local ShipBar bridge protocol`.

### Task 2: ShipBar bridge processor

**Files:**
- Create: `Sources/Mac/Bridge/ShipBarBridgeProcessor.swift`
- Modify: `Sources/Mac/ShipBarMacApp.swift`
- Modify: `Sources/Shared/Tasks/AgentRunLifecycle.swift`
- Test: `Tests/ShipBarTests/ShipBarBridgeProcessorTests.swift`

- [ ] Add failing processor tests for every command, invalid transition, missing run, wrong repo, duplicate request, and evidence validation.
- [ ] Verify RED.
- [ ] Implement processing against injected repositories, then connect it to SwiftData. Observe App Group changes while ShipBar runs and also scan on launch.
- [ ] Claim transitions `prepared → handedOff`; running and terminal commands use existing lifecycle validation and trigger sync.
- [ ] Run focused/full tests and signed Mac build; commit `feat: process Codex bridge commands`.

### Task 3: Signed `shipbarctl` helper

**Files:**
- Create: `Sources/CLI/ShipBarCLI.swift`
- Create: `Config/CLI/ShipBarCLI.entitlements`
- Modify: `project.yml`
- Test: `Tests/ShipBarTests/ShipBarCLIContractTests.swift`

- [ ] Add failing CLI contracts for JSON output, exit codes, timeout, command arguments, and no prompt-body logging.
- [ ] Add a macOS command-line target with the ShipBar App Group entitlement and embed the signed helper at `ShipBar.app/Contents/Helpers/shipbarctl`.
- [ ] Implement commands mirroring the closed protocol; write one request, notify ShipBar, wait for the matching response, print JSON to stdout, and send errors to stderr.
- [ ] Verify signing, helper path, every command against preview fixtures, and offline timeout behavior; commit `feat: add signed ShipBar command helper`.

### Task 4: Codex plugin

**Files:**
- Create: `plugins/shipbar/.codex-plugin/plugin.json`
- Create: `plugins/shipbar/skills/run-shipbar-task/SKILL.md`
- Create: `plugins/shipbar/skills/review-shipbar-run/SKILL.md`
- Create: `plugins/shipbar/README.md`

- [ ] Use the `plugin-creator` skill to scaffold and validate the plugin.
- [ ] Define the run workflow: list prepared runs, show frozen context, confirm exact run/device/repository, claim, mark running, execute normal Codex work, verify, attach evidence, and request review.
- [ ] Define failure/cancel recovery and forbid status claims not confirmed by `shipbarctl`.
- [ ] Install locally, invoke it through Codex Remote on a paired Mac, and verify ShipBar lifecycle/evidence on both devices.
- [ ] Commit `feat: add ShipBar Codex plugin`.

