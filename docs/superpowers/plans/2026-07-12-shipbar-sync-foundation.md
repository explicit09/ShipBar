# ShipBar Reliable Sync Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make phone captures durable, idempotent, and truthfully synchronized between iPhone and Mac.

**Architecture:** Replace destructive capture consumption with acknowledge-after-save queue semantics, persist the capture UUID on `ShipTask`, and add one shared actor-based sync coordinator that coalesces lifecycle and mutation-triggered CloudKit sync requests.

**Tech Stack:** Swift 6, Foundation, SwiftData, CloudKit, Swift Testing, XcodeGen.

## Global Constraints

- CloudKit private database remains the cross-device source of truth.
- `Queued` means durable locally; `Synced` requires successful CloudKit completion.
- Import is idempotent by immutable capture UUID.
- Only one direct sync runs per process; overlapping requests coalesce.
- Existing task, project, run, and tombstone reconciliation remains intact.

---

### Task 1: Acknowledge-after-save capture queue

**Files:**
- Modify: `Sources/Shared/Capture/SharedCaptureStore.swift`
- Modify: `Tests/ShipBarTests/SharedCaptureStoreTests.swift`

**Interfaces:**
- Produces: `SharedCaptureStore.pending(from:)`, `acknowledge(_:from:)`, and durable `SharedCapturePayload.schemaVersion`.

- [ ] Add failing tests proving reads do not delete, acknowledging one UUID preserves other captures, duplicate append is ignored, and legacy payload JSON decodes with schema version 1.
- [ ] Run `xcodebuild test ... -only-testing:ShipBarTests/SharedCaptureStoreTests`; expect failures because the queue APIs do not exist.
- [ ] Implement:

```swift
static func pending(from fileURL: URL) throws -> [SharedCapturePayload] { try load(from: fileURL) }

static func acknowledge(_ ids: Set<String>, from fileURL: URL) throws {
    try save(try load(from: fileURL).filter { !ids.contains($0.id) }, to: fileURL)
}
```

Make `append` ignore an existing payload ID. Add custom decoding so missing `schemaVersion` becomes `1`. Keep `consume` only as a deprecated test-compatible wrapper until all callers migrate.
- [ ] Run the focused suite; expect all queue tests to pass.
- [ ] Commit `fix: make shared capture queue durable`.

### Task 2: Persist capture identity through CloudKit

**Files:**
- Modify: `Sources/Shared/Models/ShipTask.swift`
- Modify: `Sources/Shared/Persistence/ShipBarDirectCloudSync.swift`
- Modify: `Tests/ShipBarTests/TaskLogicTests.swift`

**Interfaces:**
- Produces: `ShipTask.sourceCaptureID: String`; CloudKit field `sourceCaptureID`.

- [ ] Add failing tests proving two drafts with the same non-empty capture ID resolve to one task and empty legacy IDs do not collapse unrelated tasks.
- [ ] Run the Task Logic suite and verify RED.
- [ ] Add `sourceCaptureID` to `ShipTask`, its initializer, `TaskPayload`, local payload creation, CKRecord write, record decoding, and direct-sync apply/update paths.
- [ ] Add a pure `SharedCaptureImporter.missingCaptures(_:existingCaptureIDs:)` helper and use it during import.
- [ ] Run focused tests and the full suite; expect GREEN.
- [ ] Commit `feat: preserve capture identity across sync`.

### Task 3: Shared coalescing sync coordinator

**Files:**
- Create: `Sources/Shared/Persistence/ShipBarSyncCoordinator.swift`
- Modify: `Sources/Shared/Persistence/ShipBarDirectCloudSync.swift`
- Modify: `Sources/Mac/ShipBarMacApp.swift`
- Modify: `Sources/Shared/Views/ShipBarRootView.swift`
- Test: `Tests/ShipBarTests/ShipBarSyncCoordinatorTests.swift`

**Interfaces:**
- Produces: `ShipBarSyncStatus`, `ShipBarSyncTrigger`, and `actor ShipBarSyncCoordinator`.

- [ ] Write failing actor tests using an injected async operation: two overlapping requests execute one active pass plus one coalesced follow-up; success records a date; failure retains queued work and exposes a readable error.
- [ ] Verify RED.
- [ ] Refactor direct sync to:

```swift
static func syncOnce(modelContainer: ModelContainer) async throws -> ShipBarSyncResult
```

Propagate fetch/push errors instead of printing and swallowing them. Implement the coordinator with one `isRunning` flag and one `needsFollowUp` flag.
- [ ] Trigger it at Mac launch, iOS root `.task`, both platforms becoming active, after shared-capture import, and after task/run mutations. Add a manual retry action and truthful Settings status.
- [ ] Run coordinator tests, full macOS tests, Mac build, and iOS build when the platform is installed.
- [ ] Commit `feat: coordinate reliable CloudKit sync`.

### Task 4: Real two-device proof

**Files:**
- Create: `docs/reviews/shipbar-two-device-sync-verification.html`

- [ ] Install signed builds on the paired iPhone and Mac.
- [ ] Queue a capture while both main apps are closed; verify it remains durable.
- [ ] Open iPhone ShipBar; confirm one import and a visible queued/syncing/synced transition.
- [ ] Open Mac ShipBar; confirm exactly one matching task with full metadata.
- [ ] Repeat with Mac offline, then reconnect and verify eventual delivery without duplication.
- [ ] Record exact build hashes, timestamps, CloudKit diagnostics, screenshots, and any platform blocker in the HTML report.
- [ ] Commit `docs: verify two-device ShipBar sync`.

