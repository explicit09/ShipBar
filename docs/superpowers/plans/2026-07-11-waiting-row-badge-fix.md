# Waiting Row Badge Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep Waiting rows compact at normal and wide macOS window widths while presenting every agent-run status with consistent human-readable text.

**Architecture:** Put status copy on `AgentRunStatus` as a platform-neutral model presentation property, then consume it from every UI surface. Keep `ShipBarStateBadge` intrinsic and one-line so it cannot accept a flexible vertical proposal or surrender its label before the task title.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, Swift Testing, XcodeGen, AppKit Computer Use verification.

## Global Constraints

- Preserve task selection, completion, run state, colors, icons, accessibility descriptions, and navigation.
- Do not hard-code badge width or height.
- Verify approximately 420-point and 800-point macOS window widths.
- Do not change persistence or unrelated rows.

---

### Task 1: Share human-readable run status labels

**Files:**
- Modify: `Sources/Shared/Models/AgentRun.swift`
- Modify: `Sources/Shared/Views/ShipBarStateBadge.swift`
- Modify: `Sources/Shared/Views/ProjectWorkspaceView.swift`
- Modify: `Tests/ShipBarTests/TaskLogicTests.swift`

**Interfaces:**
- Produces: `AgentRunStatus.displayLabel: String`.
- Consumes: existing `AgentRunStatus` cases and UI state.

- [ ] **Step 1: Write the failing status-label test**

Add to `TaskLogicTests.swift`:

```swift
@Test("agent run statuses expose consistent human-readable labels")
func agentRunStatusDisplayLabels() {
    #expect(AgentRunStatus.prepared.displayLabel == "Prepared")
    #expect(AgentRunStatus.handedOff.displayLabel == "Handed off")
    #expect(AgentRunStatus.running.displayLabel == "Running")
    #expect(AgentRunStatus.needsReview.displayLabel == "Needs review")
    #expect(AgentRunStatus.completed.displayLabel == "Completed")
    #expect(AgentRunStatus.failed.displayLabel == "Failed")
    #expect(AgentRunStatus.canceled.displayLabel == "Canceled")
}
```

- [ ] **Step 2: Run RED**

Run:

```bash
xcodegen generate
xcodebuild test -project ShipBar.xcodeproj -scheme ShipBarTests \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:ShipBarTests/TaskLogicTests/agentRunStatusDisplayLabels
```

Expected: compilation fails because `AgentRunStatus` has no `displayLabel` member.

- [ ] **Step 3: Implement and consume the shared label**

Add to `AgentRunStatus` in `AgentRun.swift`:

```swift
var displayLabel: String {
    switch self {
    case .prepared: "Prepared"
    case .handedOff: "Handed off"
    case .running: "Running"
    case .needsReview: "Needs review"
    case .completed: "Completed"
    case .failed: "Failed"
    case .canceled: "Canceled"
    }
}
```

Use `runStatus.displayLabel` in `ShipBarStateBadge.init(runStatus:)` and `run.status.displayLabel` in the Project Recent Runs row. Remove the private duplicate label switch.

- [ ] **Step 4: Run GREEN**

Run the focused test from Step 2. Expected: one selected test passes.

---

### Task 2: Pin status badges to intrinsic one-line size

**Files:**
- Modify: `Sources/Shared/Views/ShipBarStateBadge.swift`
- Modify: `Sources/Shared/Views/FocusTaskRowView.swift`
- Create: `Tests/ShipBarTests/WaitingRowBadgeContractTests.swift`

**Interfaces:**
- Consumes: `ShipBarStateBadge` and `AgentRunStatus.displayLabel`.
- Produces: a compact badge that retains its label before the task title truncates.

- [ ] **Step 1: Write failing source contracts**

Create `WaitingRowBadgeContractTests.swift` that loads the two view sources and asserts:

```swift
#expect(badgeSource.contains(".lineLimit(1)"))
#expect(badgeSource.contains(".fixedSize(horizontal: true, vertical: true)"))
#expect(rowSource.contains("ShipBarStateBadge(runStatus: status)"))
#expect(rowSource.contains(".layoutPriority(2)"))
```

- [ ] **Step 2: Run RED**

Run:

```bash
xcodegen generate
xcodebuild test -project ShipBar.xcodeproj -scheme ShipBarTests \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:ShipBarTests/WaitingRowBadgeContractTests
```

Expected: the source assertions fail because intrinsic sizing and badge priority are absent.

- [ ] **Step 3: Implement the minimal layout fix**

In `ShipBarStateBadge`, apply `.lineLimit(1)` and `.fixedSize(horizontal: true, vertical: true)` to the completed label component. In the Waiting branch of `FocusTaskRowView`, apply `.layoutPriority(2)` to `ShipBarStateBadge`; retain task content at priority 1.

- [ ] **Step 4: Run GREEN**

Run the focused suite from Step 2. Expected: all selected contracts pass.

---

### Task 3: Full runtime verification and installation

**Files:**
- Verify: all files changed by Tasks 1–2.
- Update: `docs/reviews/2026-07-11-full-ui-verification.html` only if evidence changes materially.

**Interfaces:**
- Consumes: the fixed SwiftUI views and V2 preview fixture.
- Produces: a signed installed `/Applications/ShipBar.app` and runtime evidence.

- [ ] **Step 1: Run full automated verification**

Run XcodeGen, all macOS tests, a signed Release build, strict `codesign`, and `git diff --check`. Expected: 76 tests pass, build succeeds, signature is valid, and diff check is clean.

- [ ] **Step 2: Verify the real preview at both widths**

Launch with `SHIPBAR_V2_PREVIEW_DATA=1`, open Today, scroll to Waiting, and capture approximately 420-point and 800-point window widths. Expected: compact equal-height rows with complete `Running` and `Needs review` badges; Runs remains unchanged.

- [ ] **Step 3: Reinstall and launch**

Replace `/Applications/ShipBar.app` with the verified signed Release product, launch it, and confirm its process path is under `/Applications/ShipBar.app`.

- [ ] **Step 4: Commit**

```bash
git add Sources/Shared/Models/AgentRun.swift \
  Sources/Shared/Views/ShipBarStateBadge.swift \
  Sources/Shared/Views/FocusTaskRowView.swift \
  Sources/Shared/Views/ProjectWorkspaceView.swift \
  Tests/ShipBarTests/TaskLogicTests.swift \
  Tests/ShipBarTests/WaitingRowBadgeContractTests.swift \
  ShipBar.xcodeproj/project.pbxproj
git commit -m "fix: keep waiting status badges compact"
```

