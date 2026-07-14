# ShipBar macOS Navigation Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every nested macOS surface an obvious icon-only Back or Close button with a 44 × 44 point interaction target.

**Architecture:** Add one macOS-only `ShipBarNavigationIconButton` view, then compose it into existing shared views only inside `#if os(macOS)` branches. Existing dismiss closures, bindings, and keyboard shortcuts remain the source of navigation behavior; this work only makes those actions visible and consistent.

**Tech Stack:** Swift 6, SwiftUI, AppKit window presentation, Swift Testing, XcodeGen, macOS 14+

## Global Constraints

- Draw no text label inside the navigation controls.
- Use `chevron.left` for returning to a previous ShipBar surface.
- Use `xmark` for dismissing sheets, overlays, and standalone detail windows.
- Every control must have a minimum 44 × 44 point interaction target.
- Every control must expose a tooltip and VoiceOver accessibility label.
- Preserve Escape and existing keyboard shortcuts.
- Do not change iOS behavior or restructure the navigation architecture.

---

### Task 1: Reusable macOS Navigation Icon Button

**Files:**
- Create: `Sources/Mac/ShipBarNavigationIconButton.swift`
- Modify: `Tests/ShipBarTests/FinalReviewContractTests.swift`
- Regenerate: `ShipBar.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: SwiftUI `Button`, SF Symbols, `ShipBarStyle.raisedSurface`, and `ShipBarStyle.subtleStroke`.
- Produces: `ShipBarNavigationIconButton(systemImage:accessibilityLabel:action:)` with three stored properties: `String`, `String`, and `() -> Void`.

- [ ] **Step 1: Write the failing source-contract test**

Add this test to `FinalReviewContractTests`:

```swift
@Test("Mac navigation buttons are icon only, accessible, and easy to hit")
func macNavigationButtonsAreAccessibleIconOnlyControls() throws {
    let button = try self.source("Sources/Mac/ShipBarNavigationIconButton.swift")

    #expect(button.contains("struct ShipBarNavigationIconButton: View"))
    #expect(button.contains("Image(systemName: self.systemImage)"))
    #expect(button.contains(".frame(width: 44, height: 44)"))
    #expect(button.contains(".contentShape(Rectangle())"))
    #expect(button.contains(".accessibilityLabel(self.accessibilityLabel)"))
    #expect(button.contains(".help(self.accessibilityLabel)"))
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```sh
xcodebuild test -project ShipBar.xcodeproj -scheme ShipBarTests \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:ShipBarTests/FinalReviewContractTests/macNavigationButtonsAreAccessibleIconOnlyControls
```

Expected: FAIL because `Sources/Mac/ShipBarNavigationIconButton.swift` does not exist.

- [ ] **Step 3: Add the minimal shared control**

Create `Sources/Mac/ShipBarNavigationIconButton.swift`:

```swift
import SwiftUI

struct ShipBarNavigationIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            Image(systemName: self.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(ShipBarStyle.raisedSurface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(ShipBarStyle.subtleStroke))
        .accessibilityLabel(self.accessibilityLabel)
        .help(self.accessibilityLabel)
    }
}
```

- [ ] **Step 4: Regenerate the Xcode project and verify GREEN**

Run:

```sh
xcodegen generate
xcodebuild test -project ShipBar.xcodeproj -scheme ShipBarTests \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:ShipBarTests/FinalReviewContractTests/macNavigationButtonsAreAccessibleIconOnlyControls
```

Expected: PASS.

- [ ] **Step 5: Commit the shared control**

```sh
git add Sources/Mac/ShipBarNavigationIconButton.swift Tests/ShipBarTests/FinalReviewContractTests.swift ShipBar.xcodeproj/project.pbxproj
git commit -m "feat: add accessible macOS navigation button"
```

---

### Task 2: Add the Control to Every Nested macOS Surface

**Files:**
- Modify: `Sources/Shared/Views/ProjectWorkspaceView.swift`
- Modify: `Sources/Mac/WindowPresenter.swift`
- Modify: `Sources/Shared/Views/AgentRunReviewView.swift`
- Modify: `Sources/Shared/Views/ShipBarCommandPaletteView.swift`
- Modify: `Sources/Shared/Views/ShipBarRootView.swift`
- Modify: `Tests/ShipBarTests/FinalReviewContractTests.swift`

**Interfaces:**
- Consumes: `ShipBarNavigationIconButton(systemImage:accessibilityLabel:action:)` from Task 1; existing `backToProjects`, `onClose`, `dismiss`, `showGlobalCapture`, `showCommandPalette`, and `settingsSheet` state/action hooks.
- Produces: one visible icon-only navigation control on each of the six affected surfaces without changing existing state transitions.

- [ ] **Step 1: Write failing surface-coverage tests**

Replace the existing project navigation assertion and add one focused test:

```swift
@Test("Every nested Mac surface exposes an explicit navigation icon")
func everyNestedMacSurfaceExposesNavigationIcon() throws {
    let workspace = try self.source("Sources/Shared/Views/ProjectWorkspaceView.swift")
    let windows = try self.source("Sources/Mac/WindowPresenter.swift")
    let review = try self.source("Sources/Shared/Views/AgentRunReviewView.swift")
    let palette = try self.source("Sources/Shared/Views/ShipBarCommandPaletteView.swift")
    let root = try self.source("Sources/Shared/Views/ShipBarRootView.swift")

    #expect(workspace.contains("ShipBarNavigationIconButton(\n                systemImage: \"chevron.left\",\n                accessibilityLabel: \"Back to Projects\""))
    #expect(windows.contains("accessibilityLabel: \"Close task details\""))
    #expect(review.contains("accessibilityLabel: \"Close run review\""))
    #expect(palette.contains("accessibilityLabel: \"Close command palette\""))
    #expect(root.contains("accessibilityLabel: \"Cancel capture\""))
    #expect(root.contains("accessibilityLabel: \"Close settings\""))
}
```

Keep the existing assertion that `ShipBarRootView` passes `backToProjects: { self.selectedProjectID = nil }`, but replace the obsolete assertion for `Button("Back to Projects"...)` with the shared-control assertion above.

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```sh
xcodebuild test -project ShipBar.xcodeproj -scheme ShipBarTests \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:ShipBarTests/FinalReviewContractTests
```

Expected: FAIL because none of the six surfaces use `ShipBarNavigationIconButton` yet.

- [ ] **Step 3: Replace project text navigation and add task-window dismissal**

In `ProjectWorkspaceView.header`, replace the macOS text button with:

```swift
#if os(macOS)
ShipBarNavigationIconButton(
    systemImage: "chevron.left",
    accessibilityLabel: "Back to Projects",
    action: self.backToProjects)
#endif
```

In `TaskDetailWindowView.body`, wrap `TaskDetailView` in a `VStack` and add:

```swift
HStack {
    Spacer()
    ShipBarNavigationIconButton(
        systemImage: "xmark",
        accessibilityLabel: "Close task details",
        action: self.onClose)
}
.padding(.horizontal, 16)
.padding(.top, 12)
```

Keep the existing deletion closure and unavailable-task branch unchanged.

- [ ] **Step 4: Add run-review and command-palette dismissal**

At the start of `AgentRunReviewView`'s content `VStack`, add this macOS-only row:

```swift
#if os(macOS)
HStack {
    Spacer()
    ShipBarNavigationIconButton(
        systemImage: "xmark",
        accessibilityLabel: "Close run review",
        action: { self.dismiss() })
}
#endif
```

In `ShipBarCommandPaletteView`, replace the `Text("esc")` badge only on macOS:

```swift
#if os(macOS)
ShipBarNavigationIconButton(
    systemImage: "xmark",
    accessibilityLabel: "Close command palette",
    action: self.dismiss)
#else
Text("esc")
    .font(.system(size: 9, weight: .semibold, design: .monospaced))
    .foregroundStyle(.tertiary)
#endif
```

Retain `.onExitCommand(perform: self.dismiss)`.

- [ ] **Step 5: Add capture and settings dismissal**

In the macOS global capture sheet, replace the standalone `ShipBarPageHeader` with:

```swift
HStack(alignment: .top) {
    ShipBarPageHeader(title: "Capture", purpose: "Turn it into actionable work.")
    Spacer()
    ShipBarNavigationIconButton(
        systemImage: "xmark",
        accessibilityLabel: "Cancel capture",
        action: { self.showGlobalCapture = false })
}
```

In the macOS branch of `settingsSheetView`, wrap the content in:

```swift
VStack(spacing: 0) {
    HStack {
        Spacer()
        ShipBarNavigationIconButton(
            systemImage: "xmark",
            accessibilityLabel: "Close settings",
            action: { self.settingsSheet = nil })
    }
    self.settingsSheetContent(sheet)
}
.frame(width: 360)
.padding()
```

Do not change the iOS `NavigationStack` or its `Done` button.

- [ ] **Step 6: Run the focused tests and verify GREEN**

Run:

```sh
xcodebuild test -project ShipBar.xcodeproj -scheme ShipBarTests \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:ShipBarTests/FinalReviewContractTests
```

Expected: PASS.

- [ ] **Step 7: Run the full suite and build both app targets**

Run:

```sh
xcodebuild test -project ShipBar.xcodeproj -scheme ShipBarTests \
  -destination 'platform=macOS,arch=arm64' -quiet
xcodebuild build -project ShipBar.xcodeproj -scheme ShipBarMac \
  -destination 'platform=macOS,arch=arm64' -quiet
xcodebuild build -project ShipBar.xcodeproj -scheme ShipBariOS \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO -quiet
git diff --check
```

Expected: macOS tests and build PASS; iOS build PASS unless the matching simulator platform is absent, in which case record that external blocker exactly; `git diff --check` prints nothing.

- [ ] **Step 8: Commit the six-surface navigation change**

```sh
git add Sources/Shared/Views/ProjectWorkspaceView.swift Sources/Mac/WindowPresenter.swift Sources/Shared/Views/AgentRunReviewView.swift Sources/Shared/Views/ShipBarCommandPaletteView.swift Sources/Shared/Views/ShipBarRootView.swift Tests/ShipBarTests/FinalReviewContractTests.swift
git commit -m "fix: add explicit macOS navigation controls"
```

---

### Task 3: Install and Manually Verify the Real App

**Files:**
- Create: `docs/reviews/2026-07-13-macos-navigation-controls-verification.html`
- Replace installed app: `/Applications/ShipBar.app`

**Interfaces:**
- Consumes: the signed `ShipBarMac` build from Tasks 1–2 and isolated preview data.
- Produces: an installed app with verified controls plus a concise visual verification record.

- [ ] **Step 1: Build a signed isolated-review app**

Run:

```sh
rm -rf "${TMPDIR%/}/ShipBarNavigationDerivedData"
xcodebuild build -project ShipBar.xcodeproj -scheme ShipBarMac \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "${TMPDIR%/}/ShipBarNavigationDerivedData" -quiet
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 2: Replace and launch the installed app safely**

Run:

```sh
pkill -x ShipBarMac || true
ditto "${TMPDIR%/}/ShipBarNavigationDerivedData/Build/Products/Debug/ShipBarMac.app" /Applications/ShipBar.app
launchctl setenv SHIPBAR_V2_PREVIEW_DATA 1
open -na /Applications/ShipBar.app --args --open-main
launchctl unsetenv SHIPBAR_V2_PREVIEW_DATA
```

Expected: `/Applications/ShipBar.app` opens the main window with preview fixtures and Settings reports the isolated in-memory store.

- [ ] **Step 3: Click-test all six controls with Computer Use**

Verify these exact paths in the installed app:

1. Projects → project workspace → chevron returns to Projects.
2. Today → task → xmark closes the detail window.
3. Runs → run → xmark dismisses the run review.
4. Capture → xmark dismisses without creating a task.
5. Command palette → xmark closes it; reopen and confirm Escape also closes it.
6. Settings → each nested settings sheet → xmark dismisses it.

Expected: every icon is visible, comfortably clickable, dismisses only its current surface, and leaves the main app usable.

- [ ] **Step 4: Record the evidence**

Create `docs/reviews/2026-07-13-macos-navigation-controls-verification.html` with a compact six-row pass/fail table, installed app path, commit IDs, automated-test totals, and any truthful blocker. Do not include production task data or credentials.

- [ ] **Step 5: Commit the verification artifact**

```sh
git add docs/reviews/2026-07-13-macos-navigation-controls-verification.html
git commit -m "docs: verify macOS navigation controls"
```
