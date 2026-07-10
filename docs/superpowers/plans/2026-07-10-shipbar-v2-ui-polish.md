# ShipBar V2 UI Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace ShipBar’s ambiguous compact icon row with an always-labeled bottom dock, add a global command/capture strip, and apply the approved Graphite + signal hierarchy without changing V2 persistence behavior.

**Architecture:** Extract the five destinations into a shared pure enum, then compose three focused SwiftUI presentation components around the existing destination views. `ShipBarRootView` continues to own navigation, capture, and model mutations; the new shell only routes actions and displays state. Existing task, focus, project, run, persistence, and CloudKit APIs remain unchanged.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, AppKit, Swift Testing, XcodeGen, Xcode command-line builds, Computer Use against the signed macOS app.

## Global Constraints

- The default Mac review window remains 420 × 620 points.
- Mac destinations are exactly Today, Inbox, Runs, Projects, and Settings.
- `Command–1` through `Command–5` navigate those destinations in that order.
- Global capture uses the existing `CaptureBatchParser`, `CaptureDraft`, and `createTask(from:)` path.
- Workflow colors retain their existing meanings: ship blue, review amber, run purple, success green, destructive red.
- State meaning never depends on color alone.
- Existing SwiftData models and CloudKit payloads do not change.
- Preview mode remains in-memory and skips CloudKit.
- Destructive UI actions retain confirmation.
- iPhone keeps native `TabView` navigation.
- Browser-only Playwright QA is not used because the product is a native SwiftUI application.
- The missing iOS 26.4 Xcode platform remains an explicit environment blocker, not a passing build.

---

## File Structure

### New files

- `Sources/Shared/Models/ShipBarDestination.swift` — pure destination identity, labels, icons, and keyboard shortcut numbers.
- `Sources/Shared/Views/ShipBarCommandStrip.swift` — global search and capture actions.
- `Sources/Shared/Views/ShipBarDestinationDock.swift` — fixed labeled destination dock and actionable badges.
- `Sources/Shared/Views/ShipBarPageHeader.swift` — consistent destination title, purpose, and primary action.
- `docs/reviews/2026-07-10-shipbar-v2-ui-polish-qa.html` — human-readable final runtime evidence.

### Modified files

- `Sources/Shared/Views/ShipBarRootView.swift` — replace `MacFilter` and top row with the new shell; own global capture presentation.
- `Sources/Shared/Views/ShipBarStyle.swift` — Graphite surfaces, radius family, outlines, and signal helpers.
- `Sources/Shared/Views/TodayCommandCenterView.swift` — align the header and supporting hierarchy with the shell.
- `Sources/Shared/Views/InboxTriageView.swift` — page header before compact capture and dock-safe pinned batch actions.
- `Sources/Shared/Views/QuickCaptureView.swift` — configurable compact placeholder.
- `Sources/Shared/Views/AgentRunsView.swift` — shared page header and quieter secondary sections.
- `Sources/Shared/Views/ProjectWorkspaceView.swift` — explicit workspace back action and polished metrics.
- `Sources/Shared/Views/ShipBarRootView.swift` project/settings content — headers, visible New Project, progress cues, grouped diagnostics.
- `Sources/iOS/IOSTodayPane.swift` and `Sources/iOS/IOSRunsPane.swift` — reuse signal naming without replacing native tabs.
- `Tests/ShipBarTests/TaskLogicTests.swift` — destination contract and actionable-count tests.
- `project.yml` and generated `ShipBar.xcodeproj/project.pbxproj` — include new shared model/view files automatically through existing source folders.

---

### Task 1: Shared Destination Contract

**Files:**
- Create: `Sources/Shared/Models/ShipBarDestination.swift`
- Test: `Tests/ShipBarTests/TaskLogicTests.swift`

**Interfaces:**
- Consumes: `TaskQueries.todayGroups(from:runs:)`, `TaskQueries.inboxTasks(from:)`, and `AgentRunQueries.queues(from:)`.
- Produces: `ShipBarDestination`, `ShipBarDestination.actionableCount(tasks:runs:)`, `label`, `systemImage`, and `shortcutNumber` for Tasks 2–5.

- [ ] **Step 1: Write the failing destination-contract tests**

Add to `TaskLogicTests`:

```swift
@Test("destination dock has stable labels and keyboard order")
func destinationDockContractIsStable() {
    #expect(ShipBarDestination.allCases.map(\.label) == [
        "Today", "Inbox", "Runs", "Projects", "Settings",
    ])
    #expect(ShipBarDestination.allCases.map(\.shortcutNumber) == [1, 2, 3, 4, 5])
}

@Test("destination badges count only actionable work")
func destinationBadgesCountActionableWork() {
    let project = Project(name: "ShipBar")
    let focused = ShipTask(title: "Focus", focusDate: .now, focusOrder: 1, project: project)
    let due = ShipTask(title: "Due", dueDate: .now, project: project)
    let inbox = ShipTask(title: "Inbox", isInbox: true)
    let review = AgentRun(
        taskID: focused.id,
        projectID: project.id,
        taskTitleSnapshot: focused.title,
        statusRawValue: AgentRunStatus.needsReview.rawValue)
    let failed = AgentRun(
        taskID: inbox.id,
        taskTitleSnapshot: inbox.title,
        statusRawValue: AgentRunStatus.failed.rawValue)

    let tasks = [focused, due, inbox]
    let runs = [review, failed]
    #expect(ShipBarDestination.today.actionableCount(tasks: tasks, runs: runs) == 2)
    #expect(ShipBarDestination.inbox.actionableCount(tasks: tasks, runs: runs) == 1)
    #expect(ShipBarDestination.runs.actionableCount(tasks: tasks, runs: runs) == 2)
    #expect(ShipBarDestination.projects.actionableCount(tasks: tasks, runs: runs) == nil)
}
```

- [ ] **Step 2: Run the tests and verify the red state**

Run:

```bash
xcodebuild test -project ShipBar.xcodeproj -scheme ShipBarTests \
  -destination 'platform=macOS,arch=arm64' -quiet
```

Expected: compilation fails because `ShipBarDestination` does not exist.

- [ ] **Step 3: Implement the pure destination type**

Create `ShipBarDestination.swift`:

```swift
import Foundation

enum ShipBarDestination: String, CaseIterable, Identifiable {
    case today
    case inbox
    case runs
    case projects
    case settings

    var id: String { self.rawValue }

    var label: String {
        switch self {
        case .today: "Today"
        case .inbox: "Inbox"
        case .runs: "Runs"
        case .projects: "Projects"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "checkmark.circle"
        case .inbox: "tray"
        case .runs: "paperplane"
        case .projects: "folder"
        case .settings: "gearshape"
        }
    }

    var shortcutNumber: Int {
        Self.allCases.firstIndex(of: self)! + 1
    }

    func actionableCount(tasks: [ShipTask], runs: [AgentRun]) -> Int? {
        switch self {
        case .today:
            let groups = TaskQueries.todayGroups(from: tasks, runs: runs)
            return (groups.now == nil ? 0 : 1) + groups.next.count + groups.waiting.count
        case .inbox:
            return TaskQueries.inboxTasks(from: tasks).count
        case .runs:
            let queues = AgentRunQueries.queues(from: runs)
            return queues.needsReview.count + queues.recent.filter { $0.status == .failed }.count
        case .projects, .settings:
            return nil
        }
    }
}
```

- [ ] **Step 4: Generate and verify green tests**

Run:

```bash
xcodegen generate
xcodebuild test -project ShipBar.xcodeproj -scheme ShipBarTests \
  -destination 'platform=macOS,arch=arm64' -quiet
```

Expected: exit 0; destination tests pass with the existing suite.

- [ ] **Step 5: Commit the destination contract**

```bash
git add Sources/Shared/Models/ShipBarDestination.swift \
  Tests/ShipBarTests/TaskLogicTests.swift ShipBar.xcodeproj/project.pbxproj
git commit -m "refactor: define ShipBar destinations"
```

---

### Task 2: Global Command Strip and Bottom Dock

**Files:**
- Create: `Sources/Shared/Views/ShipBarCommandStrip.swift`
- Create: `Sources/Shared/Views/ShipBarDestinationDock.swift`
- Create: `Sources/Shared/Views/ShipBarPageHeader.swift`
- Modify: `Sources/Shared/Views/ShipBarRootView.swift`
- Modify: `Sources/Shared/Views/QuickCaptureView.swift`
- Modify: `Sources/Shared/Views/ShipBarStyle.swift`
- Test: `Tests/ShipBarTests/TaskLogicTests.swift`

**Interfaces:**
- Consumes: `ShipBarDestination`, existing `.shipBarOpenCapture` notification, `QuickCaptureView`, and root `createTask(from:)`.
- Produces: `ShipBarCommandStrip(openSearch:openCapture:)`, `ShipBarDestinationDock(selection:count:)`, `ShipBarPageHeader`, and global capture presentation used by every destination.

- [ ] **Step 1: Add a failing compact-capture copy test**

Extract copy into the destination model and test it:

```swift
@Test("global command copy stays compact")
func globalCommandCopyStaysCompact() {
    #expect(ShipBarDestination.searchPrompt == "Search ShipBar")
    #expect(ShipBarDestination.capturePrompt == "Capture a task…")
}
```

Expected red state: `searchPrompt` and `capturePrompt` do not exist.

- [ ] **Step 2: Add the exact copy constants**

Add to `ShipBarDestination`:

```swift
static let searchPrompt = "Search ShipBar"
static let capturePrompt = "Capture a task…"
```

Add `placeholder` to `QuickCaptureView`:

```swift
var placeholder = "Capture a task, paste a list, or add prompt after |"
```

Use `placeholder` in its `TextField`.

- [ ] **Step 3: Implement the command strip**

Before creating the strip, add the shell tokens it consumes to `ShipBarStyle`:

```swift
static var canvas: Color { Color.primary.opacity(0.012) }
static var chromeSurface: Color { Color.primary.opacity(0.052) }
static var dockSurface: Color { Color.primary.opacity(0.064) }
static var selectionSurface: Color { Self.shipBlue.opacity(0.13) }
static var badgeSurface: Color { Self.reviewAmber }
static let pageRadius: CGFloat = 13
static let rowRadius: CGFloat = 10
```

Create `ShipBarCommandStrip.swift`:

```swift
import SwiftUI

struct ShipBarCommandStrip: View {
    let openSearch: () -> Void
    let openCapture: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: self.openSearch) {
                HStack(spacing: 7) {
                    Image(systemName: "command")
                    Text(ShipBarDestination.searchPrompt)
                    Spacer()
                    Text("K").font(.system(size: 9, weight: .bold, design: .monospaced))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(ShipBarCommandStripButtonStyle())
            .keyboardShortcut("k", modifiers: .command)
            .accessibilityLabel("Search ShipBar, Command K")

            Button(action: self.openCapture) {
                Image(systemName: "plus")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(ShipBarCommandStripButtonStyle())
            .accessibilityLabel("Global capture")
        }
    }
}

private struct ShipBarCommandStripButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(configuration.isPressed ? ShipBarStyle.shipBlue : Color.secondary)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                configuration.isPressed
                    ? ShipBarStyle.selectionSurface
                    : ShipBarStyle.chromeSurface,
                in: RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(ShipBarStyle.subtleStroke, lineWidth: 1))
    }
}
```

- [ ] **Step 4: Implement the destination dock**

Create `ShipBarDestinationDock.swift`:

```swift
import SwiftUI

struct ShipBarDestinationDock: View {
    @Binding var selection: ShipBarDestination
    let count: (ShipBarDestination) -> Int?

    var body: some View {
        HStack(spacing: 3) {
            ForEach(ShipBarDestination.allCases) { destination in
                Button { self.selection = destination } label: {
                    VStack(spacing: 3) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: destination.systemImage)
                                .font(.system(size: 13, weight: .semibold))
                            if let count = self.count(destination), count > 0 {
                                Text("\(count)")
                                    .font(.system(size: 8, weight: .bold, design: .rounded))
                                    .padding(.horizontal, 4)
                                    .frame(minWidth: 14, minHeight: 14)
                                    .background(ShipBarStyle.badgeSurface, in: Capsule())
                                    .offset(x: 10, y: -6)
                            }
                        }
                        Text(destination.label)
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(self.selection == destination ? ShipBarStyle.shipBlue : .secondary)
                    .background(
                        self.selection == destination ? ShipBarStyle.selectionSurface : .clear,
                        in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(
                    KeyEquivalent(Character("\(destination.shortcutNumber)")),
                    modifiers: .command)
                .accessibilityLabel(destination.label)
                .accessibilityValue(self.count(destination).map { "\($0) actionable" } ?? "")
            }
        }
        .padding(6)
        .background(ShipBarStyle.dockSurface, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(ShipBarStyle.subtleStroke))
    }
}
```

- [ ] **Step 5: Implement the shared page header**

Create `ShipBarPageHeader.swift`:

```swift
import SwiftUI

struct ShipBarPageHeader<Action: View>: View {
    let eyebrow: String?
    let title: String
    let purpose: String
    let action: () -> Action

    init(
        eyebrow: String? = nil,
        title: String,
        purpose: String,
        @ViewBuilder action: @escaping () -> Action)
    {
        self.eyebrow = eyebrow
        self.title = title
        self.purpose = purpose
        self.action = action
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                if let eyebrow {
                    Text(eyebrow)
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(ShipBarStyle.shipBlue)
                }
                Text(self.title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .tracking(-0.4)
                Text(self.purpose)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            self.action()
        }
    }
}

extension ShipBarPageHeader where Action == EmptyView {
    init(eyebrow: String? = nil, title: String, purpose: String) {
        self.init(eyebrow: eyebrow, title: title, purpose: purpose) { EmptyView() }
    }
}
```

- [ ] **Step 6: Compose the fixed Mac shell and global capture**

In `ShipBarRootView`, add:

```swift
@State private var showGlobalCapture = false
@State private var macDestination = ShipBarDestination.today
```

Replace `macBody` with:

```swift
private var macBody: some View {
    VStack(spacing: 10) {
        ShipBarCommandStrip(
            openSearch: { self.showCommandPalette = true },
            openCapture: { self.showGlobalCapture = true })

        self.macDestinationContent
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()

        ShipBarDestinationDock(
            selection: self.$macDestination,
            count: { $0.actionableCount(tasks: self.tasks, runs: self.agentRuns) })
    }
    .padding(.horizontal, ShipBarStyle.contentPadding)
    .padding(.top, 10)
    .padding(.bottom, 10)
    .background(ShipBarStyle.canvas)
    .sheet(isPresented: self.$showGlobalCapture) {
        VStack(alignment: .leading, spacing: 12) {
            ShipBarPageHeader(title: "Capture", purpose: "Turn it into actionable work.")
            QuickCaptureView(
                projects: self.projects,
                selectedProjectID: self.selectedProjectID,
                createTask: { draft in
                    self.createTask(from: draft)
                    self.showGlobalCapture = false
                },
                autoFocus: true,
                placeholder: ShipBarDestination.capturePrompt)
        }
        .padding(18)
        .frame(width: 420, height: 150)
    }
}
```

Remove the nested `MacFilter` enum and old `macFilter` state. Rename the existing `macFilterContent` computed property to `macDestinationContent`, switch on `self.macDestination`, and keep its five existing destination bodies unchanged for this task.

Remove the old top filter bar and hidden duplicate Command–K button.

- [ ] **Step 7: Verify tests and signed build**

```bash
xcodegen generate
xcodebuild test -project ShipBar.xcodeproj -scheme ShipBarTests \
  -destination 'platform=macOS,arch=arm64' -quiet
xcodebuild build -project ShipBar.xcodeproj -scheme ShipBarMac \
  -destination 'platform=macOS,arch=arm64' -quiet
```

Expected: both exit 0.

- [ ] **Step 8: Inspect the shell with Computer Use**

Launch the signed app with `--open-main`. At 420 × 620 verify:

- All five labels are visible.
- Dock does not scroll.
- Command strip does not truncate.
- Command–K opens search.
- Global capture opens, accepts a fixture task, and closes.
- Command–1 through Command–5 change destinations.

- [ ] **Step 9: Commit the shell**

```bash
git add Sources/Shared/Models/ShipBarDestination.swift \
  Sources/Shared/Views/ShipBarCommandStrip.swift \
  Sources/Shared/Views/ShipBarDestinationDock.swift \
  Sources/Shared/Views/ShipBarPageHeader.swift \
  Sources/Shared/Views/ShipBarRootView.swift \
  Sources/Shared/Views/ShipBarStyle.swift \
  Sources/Shared/Views/QuickCaptureView.swift \
  Tests/ShipBarTests/TaskLogicTests.swift ShipBar.xcodeproj/project.pbxproj
git commit -m "feat: add the ShipBar command shell"
```

---

### Task 3: Destination Hierarchy Polish

**Files:**
- Modify: `Sources/Shared/Views/TodayCommandCenterView.swift`
- Modify: `Sources/Shared/Views/InboxTriageView.swift`
- Modify: `Sources/Shared/Views/AgentRunsView.swift`
- Modify: `Sources/Shared/Views/ProjectWorkspaceView.swift`
- Modify: `Sources/Shared/Views/ShipBarRootView.swift`
- Modify: `Sources/Shared/Views/QuickCaptureView.swift`
- Test: `Tests/ShipBarTests/TaskLogicTests.swift`

**Interfaces:**
- Consumes: `ShipBarPageHeader`, existing destination actions, `ProjectQueries.health`, and all V2 mutation closures.
- Produces: consistent page hierarchy across populated and empty destinations without changing behavior.

- [ ] **Step 1: Add a failing project-list summary test**

```swift
@Test("project health progress includes completed work")
func projectHealthProgressIncludesCompletedWork() {
    let project = Project(name: "ShipBar")
    let open = ShipTask(title: "Open", project: project)
    let done = ShipTask(title: "Done", status: .done, completedAt: .now, project: project)
    let health = ProjectQueries.health(project: project, tasks: [open, done], runs: [])
    #expect(health.progress == 0.5)
}
```

Expected: pass if existing behavior is intact. Temporarily assert `0.75` first to prove the test executes and fails, then restore `0.5` before production edits.

- [ ] **Step 2: Apply consistent page headers**

- Today: preserve its date, current target, and completion ring inside its current `progressHeader`; do not nest a second title.
- Inbox: render `ShipBarPageHeader(title: "Inbox", purpose: "Clarify, schedule, or discard captured work.")` before `QuickCaptureView`.
- Runs: replace the custom header with `ShipBarPageHeader(title: "Agent runs", purpose: "Delegate the work. Keep the decision.")`.
- Projects list: render `ShipBarPageHeader(title: "Projects", purpose: "Outcomes, focus, and agent activity.")` with a `New Project` button.
- Settings: render `ShipBarPageHeader(title: "Settings", purpose: "Storage, capture, and product details.")`.

- [ ] **Step 3: Make Inbox dock-safe and compact**

Use `ShipBarDestination.capturePrompt` in the Inbox capture field. Keep its batch action bar in `safeAreaInset(edge: .bottom)` so it remains immediately above the dock instead of reducing the scroll viewport:

```swift
.safeAreaInset(edge: .bottom) {
    if !self.selection.isEmpty { self.batchBar.padding(.top, 6) }
}
```

Remove the old inline batch-bar placement. Preserve the cancel shortcut and delete confirmation.

- [ ] **Step 4: Add project-list progress cues and a visible create action**

Pass `createProject` into the project-list content from Root. For every project, compute:

```swift
let projectTasks = self.tasks.filter { $0.project?.id == project.id }
let health = ProjectQueries.health(project: project, tasks: projectTasks, runs: self.agentRuns)
```

Render name, outcome when present, open count, and a 48-point progress bar using `health.progress`. The header’s New Project button calls the existing root `createProject()` method.

- [ ] **Step 5: Group Settings diagnostics**

Wrap CloudKit, Share Sheet Inbox, and Local Saves rows in one Graphite card with internal dividers. Wrap Prompt Templates and About in a second card. Preserve every current status/detail string exactly, including preview mode.

- [ ] **Step 6: Refine Today and Runs hierarchy**

- Keep Flight Plan’s existing blue outline and position menu.
- Reduce Next/Waiting supporting card fill by one opacity tier.
- Keep Needs Review first and use both `ShipBarStateBadge` and section text.
- Ensure failed runs are visually red and remain in Recent.
- Do not remove any row action or accessibility label.

- [ ] **Step 7: Run tests and build**

Run the full macOS suite and signed build commands from Task 2. Expected: exit 0.

- [ ] **Step 8: Inspect every populated and empty destination**

Use isolated preview mode for populated states. Relaunch without preview for the user’s real empty/sparse states. Verify title, purpose, primary action, scroll boundaries, and no content behind the dock.

- [ ] **Step 9: Commit destination polish**

```bash
git add Sources/Shared/Views/TodayCommandCenterView.swift \
  Sources/Shared/Views/InboxTriageView.swift \
  Sources/Shared/Views/AgentRunsView.swift \
  Sources/Shared/Views/ProjectWorkspaceView.swift \
  Sources/Shared/Views/ShipBarRootView.swift \
  Sources/Shared/Views/QuickCaptureView.swift \
  Tests/ShipBarTests/TaskLogicTests.swift
git commit -m "feat: clarify ShipBar destination hierarchy"
```

---

### Task 4: Graphite + Signal and Accessibility Pass

**Files:**
- Modify: `Sources/Shared/Views/ShipBarStyle.swift`
- Modify: `Sources/Shared/Views/ShipBarCommandStrip.swift`
- Modify: `Sources/Shared/Views/ShipBarDestinationDock.swift`
- Modify: `Sources/Shared/Views/ShipBarPageHeader.swift`
- Modify: `Sources/Shared/Views/FocusTaskRowView.swift`
- Modify: `Sources/Shared/Views/TaskRowView.swift`
- Modify: `Sources/Shared/Views/AgentRunsView.swift`
- Modify: `Sources/iOS/IOSTodayPane.swift`
- Modify: `Sources/iOS/IOSRunsPane.swift`

**Interfaces:**
- Consumes: existing signal colors and environment accessibility values.
- Produces: consistent Graphite surfaces, outlines, focus treatment, non-color labels, and dock-safe iPhone alignment.

- [ ] **Step 1: Verify and tune the Graphite surface tokens**

Task 2 introduced the complete token contract below. Keep the names stable and tune only opacity after inspecting the signed app:

```swift
static var canvas: Color { Color.primary.opacity(0.012) }
static var chromeSurface: Color { Color.primary.opacity(0.052) }
static var dockSurface: Color { Color.primary.opacity(0.064) }
static var selectionSurface: Color { Self.shipBlue.opacity(0.13) }
static var badgeSurface: Color { Self.reviewAmber }
static let pageRadius: CGFloat = 13
static let rowRadius: CGFloat = 10
```

Keep the existing semantic colors and `colorSchemeContrast` outline behavior.

- [ ] **Step 2: Apply one radius and outline hierarchy**

- Shell/dock/Flight Plan: `pageRadius`.
- Rows/diagnostic cards: `rowRadius`.
- Inputs and compact controls: existing `controlRadius`.
- Increased Contrast uses two-pixel outlines through the existing `ShipBarGlassSurface` environment check.

- [ ] **Step 3: Add visible keyboard focus and complete labels**

Use native focusability on command-strip and dock buttons. Every dock label includes destination and actionable count. Every run row continues to include task, textual status, and agent. Every focus row keeps position/current/waiting text.

- [ ] **Step 4: Preserve reduced motion and iPhone hit targets**

Keep Root’s transaction animation suppression. Verify every iPhone tab/list/review action remains at least 44 points. Do not replace native `TabView`.

- [ ] **Step 5: Build and visually compare compact and wide layouts**

Build signed Mac. Inspect at 420 × 620, then widen to at least 720 points. The dock remains centered and capped so labels do not stretch excessively; page content gains whitespace instead of larger typography.

- [ ] **Step 6: Commit the visual system**

```bash
git add Sources/Shared/Views/ShipBarStyle.swift \
  Sources/Shared/Views/ShipBarCommandStrip.swift \
  Sources/Shared/Views/ShipBarDestinationDock.swift \
  Sources/Shared/Views/ShipBarPageHeader.swift \
  Sources/Shared/Views/FocusTaskRowView.swift \
  Sources/Shared/Views/TaskRowView.swift \
  Sources/Shared/Views/AgentRunsView.swift \
  Sources/iOS/IOSTodayPane.swift Sources/iOS/IOSRunsPane.swift
git commit -m "feat: apply Graphite and signal styling"
```

---

### Task 5: Full Native Feature QA and Review Artifact

**Files:**
- Create: `docs/reviews/2026-07-10-shipbar-v2-ui-polish-qa.html`
- Modify: `README.md`

**Interfaces:**
- Consumes: the signed Mac app, `SHIPBAR_V2_PREVIEW_DATA=1`, existing test suite, and every V2 surface.
- Produces: exact automated results, native runtime evidence, known blockers, and rerun instructions.

- [ ] **Step 1: Run final automated verification**

```bash
pkill -x ShipBarMac || true
xcodegen generate
xcodebuild test -project ShipBar.xcodeproj -scheme ShipBarTests \
  -destination 'platform=macOS,arch=arm64' -quiet
xcodebuild build -project ShipBar.xcodeproj -scheme ShipBarMac \
  -destination 'platform=macOS,arch=arm64' -quiet
git diff --check
```

Record exit codes and any warnings in the QA artifact. Do not call the suite passing unless exit code is 0.

- [ ] **Step 2: Re-attempt the iOS simulator build**

```bash
xcodebuild build -project ShipBar.xcodeproj -scheme ShipBariOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO -quiet
```

Expected on the current machine: exit 70 before compilation with “iOS 26.4 is not installed.” Record this as blocked, not passing.

- [ ] **Step 3: Launch isolated preview mode safely**

```bash
launchctl setenv SHIPBAR_V2_PREVIEW_DATA 1
open -na "$HOME/Library/Developer/Xcode/DerivedData/ShipBar-aidgviwwzrjwxnbmohonoazehacd/Build/Products/Debug/ShipBarMac.app" --args --open-main
launchctl unsetenv SHIPBAR_V2_PREVIEW_DATA
```

Confirm Settings says “Preview only” and “CloudKit sync is disabled.”

- [ ] **Step 4: Exercise the complete non-destructive native workflow with Computer Use**

Verify and record:

1. Today: Flight Plan add menu, reorder, remove presentation, Now, Next, Waiting, Completed.
2. Command strip: Command–K opens palette; global capture creates an in-memory task.
3. Dock: all labels; badges; mouse and Command–1 through Command–5 navigation.
4. Inbox: select one and multiple; Escape clears; Project, Today, and Someday actions; Delete dialog opens and is canceled.
5. Task detail: title, description, prompt, status, priority, project, type, and due controls are present; do not delete real data.
6. Runs: Needs Review, Active, Recent, completed, and failed states; open review; summary/evidence fields; Accept, Request Changes, failure, and cancel presentation.
7. Projects: list header, New Project entry point, outcome, repo, prompt, health counts, progress, scoped capture, task sections, recent runs.
8. Settings: preview truth labels, diagnostics cards, Prompt Templates, About.
9. Empty states: relaunch normal store and inspect any naturally empty destination; use fixture tests for states not safely reachable.
10. Window sizes: 420 × 620 and at least 720 points wide.

Computer Use deletion policy: opening a delete confirmation is allowed, but do not click the final destructive action without fresh user confirmation. Unit lifecycle tests provide deletion behavior evidence.

- [ ] **Step 5: Verify keyboard and accessibility behavior**

Check accessibility trees for named dock destinations, actionable badge values, command strip controls, task rows, run status text, and review actions. Verify Escape clears Inbox selection. Confirm reduced-motion code path and increased-contrast outlines by code inspection if OS toggles cannot be changed without user confirmation.

- [ ] **Step 6: Write the interactive QA artifact**

Create a one-screen HTML report with tabs for:

- Automated
- Navigation
- Workflows
- Accessibility
- Blockers

Each item must be `Passed`, `Failed`, or `Blocked` with an evidence note. Put the HTML path before any Markdown path in the handoff.

- [ ] **Step 7: Update README rerun instructions**

Document the bottom dock, command strip, Command–1 through Command–5 shortcuts, isolated preview launch, automated commands, and the iOS platform blocker.

- [ ] **Step 8: Run verification after documentation changes**

Run `git diff --check`, the full macOS test suite, and signed Mac build again. Expected: exit 0.

- [ ] **Step 9: Commit QA and documentation**

```bash
git add README.md docs/reviews/2026-07-10-shipbar-v2-ui-polish-qa.html
git commit -m "docs: record ShipBar V2 UI QA"
```

## Final Completion Gate

- [ ] Working tree is clean.
- [ ] All macOS tests exit 0.
- [ ] Signed Mac build exits 0.
- [ ] `git diff --check` exits 0.
- [ ] All five destination names remain visible at 420 points.
- [ ] Command strip search and capture work in the signed app.
- [ ] Command–1 through Command–5 navigate correctly.
- [ ] Today, Inbox, Runs, Projects, and Settings pass populated and safe empty-state checks.
- [ ] Keyboard and accessibility labels are confirmed from the live accessibility tree.
- [ ] No user data is deleted during Computer Use QA.
- [ ] The iOS build is reported as blocked unless the missing platform becomes available and the command exits 0.
- [ ] The HTML QA artifact contains exact evidence and known limitations.
