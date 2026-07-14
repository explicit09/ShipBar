# CodexBar Width Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep ShipBar's rendered status menu near CodexBar's 310-point base width even when task or project names are unusually long.

**Architecture:** Continue using native `NSMenu` rows and constrain only user-controlled text before AppKit measures the menu. Introduce an explicit 310-point menu target, a 200-point dynamic-label budget that leaves room for native chrome, and a smaller metadata budget so project context does not crowd out the task title.

**Tech Stack:** Swift 6, AppKit `NSMenu`, Swift Testing, Xcode/xcodebuild

## Global Constraints

- Target a rendered menu width between 310 and 320 points.
- Preserve every existing menu section, action, shortcut, and submenu.
- Long task and project names use one trailing ellipsis and retain full tooltips.
- Do not replace `NSMenu` with a custom popover.

---

### Task 1: Lock the Compact Sizing Contract

**Files:**
- Modify: `Tests/ShipBarTests/StatusMenuTextFitterTests.swift`
- Modify: `Sources/Mac/StatusItemMenuController.swift`

**Interfaces:**
- Consumes: `StatusMenuTextFitter.projectLabel(name:count:font:maxWidth:)` and `StatusMenuTextFitter.taskTitle(_:font:fixedWidth:maxWidth:)`
- Produces: `StatusItemMenuController.targetMenuWidth`, `dynamicLabelWidth`, and `taskMetadataWidth` sizing constants used by every dynamic status-menu row

- [ ] **Step 1: Write the failing sizing contract**

Replace the old 360-point controller assertion and add compact task/project fitting checks:

```swift
#expect(source.contains("targetMenuWidth: CGFloat = 310"))
#expect(source.contains("dynamicLabelWidth: CGFloat = 200"))
#expect(source.contains("taskMetadataWidth: CGFloat = 72"))
#expect(source.contains("menu.minimumWidth = Self.targetMenuWidth"))

let compactProject = StatusMenuTextFitter.projectLabel(
    name: String(repeating: "Very long project name ", count: 8),
    count: 12,
    font: NSFont.menuFont(ofSize: 0),
    maxWidth: 200)
#expect(StatusMenuTextFitter.width(of: compactProject, font: NSFont.menuFont(ofSize: 0)) <= 200)

let compactTask = StatusMenuTextFitter.taskTitle(
    "Refine podcast guest questions to encourage monologue-friendly answers for social clips",
    font: self.font,
    fixedWidth: 88,
    maxWidth: 200)
#expect(compactTask.hasSuffix("…"))
#expect(StatusMenuTextFitter.width(of: compactTask, font: self.font) <= 112)
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
xcodebuild test -project ShipBar.xcodeproj -scheme ShipBarTests \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:ShipBarTests/StatusMenuTextFitterTests -quiet
```

Expected: FAIL because `StatusItemMenuController.swift` still declares `dynamicLabelWidth` as 360 and does not declare the 310-point target or 72-point metadata budget.

- [ ] **Step 3: Implement the minimum sizing change**

Replace the controller constants with:

```swift
private static let targetMenuWidth: CGFloat = 310
private static let dynamicLabelWidth: CGFloat = 200
private static let taskMetadataWidth: CGFloat = 72
```

Use `targetMenuWidth` to set the native menu's baseline without allowing dynamic strings to widen it:

```swift
let menu = NSMenu()
menu.autoenablesItems = false
menu.minimumWidth = Self.targetMenuWidth
```

- [ ] **Step 4: Run focused and complete tests**

Run:

```bash
xcodebuild test -project ShipBar.xcodeproj -scheme ShipBarTests \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:ShipBarTests/StatusMenuTextFitterTests -quiet
xcodebuild test -project ShipBar.xcodeproj -scheme ShipBarTests \
  -destination 'platform=macOS,arch=arm64' -quiet
```

Expected: all focused tests pass, followed by the complete suite passing with no failures.

- [ ] **Step 5: Commit the sizing change**

```bash
git add Sources/Mac/StatusItemMenuController.swift Tests/ShipBarTests/StatusMenuTextFitterTests.swift
git commit -m "fix: match CodexBar status menu width"
```

### Task 2: Build, Install, and Verify the Real Menu

**Files:**
- Modify only if verification reveals a sizing regression: `Sources/Mac/StatusItemMenuController.swift`
- Test only if a regression is found: `Tests/ShipBarTests/StatusMenuTextFitterTests.swift`

**Interfaces:**
- Consumes: the compact menu constants and existing macOS packaging/install workflow
- Produces: a rebuilt `/Applications/ShipBar.app` whose visible menu stays near the installed CodexBar reference width

- [ ] **Step 1: Build the macOS product**

Run:

```bash
rm -rf "${TMPDIR%/}/ShipBarWidthDerivedData"
xcodebuild build -project ShipBar.xcodeproj -scheme ShipBarMac \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "${TMPDIR%/}/ShipBarWidthDerivedData" -quiet
```

Expected: build completes successfully.

- [ ] **Step 2: Package and install ShipBar**

Run:

```bash
pkill -x ShipBarMac || true
ditto "${TMPDIR%/}/ShipBarWidthDerivedData/Build/Products/Debug/ShipBarMac.app" /Applications/ShipBar.app
open -na /Applications/ShipBar.app
```

Expected: the running `ShipBarMac` executable resolves beneath `/Applications/ShipBar.app`.

- [ ] **Step 3: Verify the menu with long fixture data**

Open ShipBar from the menu bar and confirm:

- the outer menu is visually the same width as CodexBar, within the 310–320 point target;
- the long task title ends in one ellipsis;
- the project metadata remains readable and does not push the menu wider;
- shortcuts and submenu arrows remain visible;
- hovering the long task and project exposes the complete title.

- [ ] **Step 4: Re-run the full verification suite**

Run:

```bash
xcodebuild test -project ShipBar.xcodeproj -scheme ShipBarTests \
  -destination 'platform=macOS,arch=arm64' -quiet
xcodebuild build -project ShipBar.xcodeproj -scheme ShipBarMac \
  -destination 'platform=macOS,arch=arm64' -quiet
git status --short
```

Expected: tests and build pass; the worktree contains no unexpected files.
