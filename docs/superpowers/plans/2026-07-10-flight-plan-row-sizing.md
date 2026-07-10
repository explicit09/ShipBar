# Flight Plan Row Sizing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep Flight Plan task rows compact and parent-width-bound when titles are long, while preserving the full title for hover, task detail, and accessibility.

**Architecture:** Keep the existing shared `FocusTaskRowView` and derive sizing from its existing `.flightPlan` mode. Constrain only that mode to one title line and a 48-point row; Now, Next, Waiting, and Completed retain two-line titles and current sizing.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing, XcodeGen, signed macOS runtime, Computer Use.

## Global Constraints

- Flight Plan rows use one title line with tail truncation.
- Flight Plan rows remain 48 points high and never request more width than their parent.
- Position and remove controls keep their existing fixed sizes and actions.
- Full titles remain available through hover help, task detail, and the existing accessibility label.
- Non-Flight-Plan focus rows retain their existing two-line behavior.
- No model, persistence, CloudKit, or iOS behavior changes.

---

### Task 1: Constrain Flight Plan rows

**Files:**
- Modify: `Sources/Shared/Views/FocusTaskRowView.swift:19-87`
- Test: `Tests/ShipBarTests/FinalReviewContractTests.swift`

**Interfaces:**
- Consumes: existing `FocusTaskRowMode.flightPlan(position:)`, `ShipTask.title`, selection, reorder, and removal closures.
- Produces: mode-scoped title line limit, width constraint, 48-point row height, and full-title hover help.

- [ ] **Step 1: Add the failing sizing contract**

Add inside `FinalReviewContractTests`:

```swift
@Test("Flight Plan rows contain long titles without changing workflow rows")
func flightPlanRowsContainLongTitles() throws {
    let row = try self.source("Sources/Shared/Views/FocusTaskRowView.swift")

    #expect(row.contains(".lineLimit(self.isFlightPlan ? 1 : 2)"))
    #expect(row.contains(".truncationMode(.tail)"))
    #expect(row.contains(".frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)"))
    #expect(row.contains(".frame(maxWidth: .infinity)"))
    #expect(row.contains(".frame(height: self.isFlightPlan ? 48 : nil)"))
    #expect(row.contains(".help(self.task.title)"))
}
```

- [ ] **Step 2: Run the focused contract and confirm RED**

Run:

```bash
xcodegen generate
xcodebuild test -project ShipBar.xcodeproj -scheme ShipBarTests \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:ShipBarTests/FinalReviewContractTests/flightPlanRowsContainLongTitles -quiet
```

Expected: exit 65 because the mode-scoped line limit, width/height constraints, and title help do not exist.

- [ ] **Step 3: Implement the minimal mode-scoped sizing**

In the task title block, replace the fixed line limit and constrain the label column:

```swift
Text(self.task.title)
    .font(.system(size: self.isNow ? 14 : 13, weight: self.isNow ? .semibold : .medium))
    .foregroundStyle(.primary)
    .lineLimit(self.isFlightPlan ? 1 : 2)
    .truncationMode(.tail)
    .multilineTextAlignment(.leading)

HStack(spacing: 5) {
    Text(self.task.project?.name ?? "Inbox")
    if let dueLabel {
        Text("·")
        Text(dueLabel)
    }
}
.font(.system(size: 10, weight: .medium))
.foregroundStyle(.secondary)
.lineLimit(1)
.truncationMode(.tail)
```

Constrain the label and expose the full title:

```swift
.frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
.contentShape(Rectangle())
}
.buttonStyle(.plain)
.layoutPriority(1)
.help(self.task.title)
```

Constrain the complete row after its padding:

```swift
.frame(maxWidth: .infinity)
.frame(height: self.isFlightPlan ? 48 : nil)
```

Add the private mode predicate:

```swift
private var isFlightPlan: Bool {
    if case .flightPlan = self.mode { return true }
    return false
}
```

- [ ] **Step 4: Run focused and full GREEN verification**

Run:

```bash
xcodebuild test -project ShipBar.xcodeproj -scheme ShipBarTests \
  -destination 'platform=macOS,arch=arm64' -quiet
xcodebuild build -project ShipBar.xcodeproj -scheme ShipBarMac \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "${TMPDIR%/}/ShipBarRowSizing" -quiet
codesign --verify --deep --strict --verbose=2 \
  "${TMPDIR%/}/ShipBarRowSizing/Build/Products/Debug/ShipBarMac.app"
git diff --check
```

Expected: 67 tests pass, signed build and code-sign verification exit 0, and diff check is clean.

- [ ] **Step 5: Verify the signed layout with a long preview title**

Launch isolated preview mode from `${TMPDIR%/}/ShipBarRowSizing`. Use global capture to create a deliberately long title, add it to Flight Plan, and inspect at 420 × 620 and at least 720 points wide.

Confirm:

- the title truncates on one line;
- each Flight Plan row remains 48 points high;
- the card never widens beyond its parent;
- reorder and remove controls remain visible and actionable;
- hover/AX retains the complete title;
- Now and Next still allow their existing two-line presentation.

Unset `SHIPBAR_V2_PREVIEW_DATA` after launch and do not mutate the normal store.

- [ ] **Step 6: Review and commit**

Review the task diff for spec compliance and code quality, then run the final commands again. Commit only the source and test changes:

```bash
git add Sources/Shared/Views/FocusTaskRowView.swift \
  Tests/ShipBarTests/FinalReviewContractTests.swift
git commit -m "fix: contain long Flight Plan titles"
```

