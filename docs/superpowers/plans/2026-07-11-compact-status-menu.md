# Compact Status Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent dynamic task or project names from expanding ShipBar's native status menu beyond an approximately 480-point total width.

**Architecture:** Add a macOS-only, grapheme-safe rendered-width fitter and use it while constructing native task and project `NSMenuItem` labels. Preserve native menus, attributed metadata, submenus, shortcuts, full-title tooltips, and existing actions.

**Tech Stack:** Swift 6, AppKit `NSMenu`, SwiftData, Swift Testing, XcodeGen, signed macOS app.

## Global Constraints

- Keep native `NSMenu` and `NSMenuItem` behavior.
- Dynamic attributed label budget is 400 points; expected total menu width is approximately 480 points.
- Truncation is rendered-width-based, grapheme-safe, and uses one ellipsis.
- Short labels remain unchanged.
- Task and project tooltips retain complete titles.
- Static menu rows, shortcuts, actions, icons, and submenus remain unchanged.

---

### Task 1: Fit dynamic native-menu labels

**Files:**
- Create: `Sources/Mac/StatusMenuTextFitter.swift`
- Create: `Tests/ShipBarTests/StatusMenuTextFitterTests.swift`
- Modify: `Sources/Mac/StatusItemMenuController.swift:83-122,182-270`
- Modify: `project.yml:121-134`

**Interfaces:**
- Produces: `StatusMenuTextFitter.fitted(_:font:maxWidth:) -> String` and `StatusMenuTextFitter.width(of:font:) -> CGFloat`.
- Consumes: native menu fonts, task titles/metadata, project names/counts.

- [ ] **Step 1: Add failing unit and integration contracts**

Create `StatusMenuTextFitterTests.swift` with four tests:

```swift
import AppKit
import Foundation
import Testing

@Suite("Status menu text fitting")
struct StatusMenuTextFitterTests {
    private let font = NSFont.systemFont(ofSize: 13)

    @Test("short labels remain unchanged")
    func shortLabelsRemainUnchanged() {
        #expect(StatusMenuTextFitter.fitted("ShipBar", font: self.font, maxWidth: 400) == "ShipBar")
    }

    @Test("long labels fit the rendered width with one ellipsis")
    func longLabelsFitRenderedWidth() {
        let source = "Refine podcast guest questions to encourage monologue-friendly answers for social clips"
        let fitted = StatusMenuTextFitter.fitted(source, font: self.font, maxWidth: 220)
        #expect(fitted.hasSuffix("…"))
        #expect(fitted.filter { $0 == "…" }.count == 1)
        #expect(StatusMenuTextFitter.width(of: fitted, font: self.font) <= 220)
    }

    @Test("truncation preserves grapheme clusters")
    func truncationPreservesGraphemes() {
        let family = "👨‍👩‍👧‍👦"
        let fitted = StatusMenuTextFitter.fitted(String(repeating: family, count: 12), font: self.font, maxWidth: 80)
        #expect(fitted.hasSuffix("…"))
        #expect(fitted.dropLast().allSatisfy { String($0) == family })
    }

    @Test("task and project items use fitting and full-title tooltips")
    func controllerUsesFittingAndTooltips() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/Mac/StatusItemMenuController.swift"), encoding: .utf8)
        #expect(source.contains("StatusMenuTextFitter.fitted"))
        #expect(source.contains("item.toolTip = task.title"))
        #expect(source.contains("item.toolTip = project.name"))
    }
}
```

Add `Sources/Mac/StatusMenuTextFitter.swift` to the `ShipBarTests` source list in `project.yml`.

- [ ] **Step 2: Run RED**

Run `xcodegen generate`, then the `StatusMenuTextFitterTests` suite. Expected: exit 65 because `StatusMenuTextFitter` does not exist.

- [ ] **Step 3: Implement the grapheme-safe fitter**

Create:

```swift
import AppKit

enum StatusMenuTextFitter {
    static func width(of text: String, font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    static func fitted(_ text: String, font: NSFont, maxWidth: CGFloat) -> String {
        guard maxWidth > 0, self.width(of: text, font: font) > maxWidth else { return text }
        let characters = Array(text)
        let ellipsis = "…"
        guard self.width(of: ellipsis, font: font) <= maxWidth else { return "" }

        var lower = 0
        var upper = characters.count
        while lower < upper {
            let candidateCount = (lower + upper + 1) / 2
            let candidate = String(characters.prefix(candidateCount)) + ellipsis
            if self.width(of: candidate, font: font) <= maxWidth {
                lower = candidateCount
            } else {
                upper = candidateCount - 1
            }
        }
        return String(characters.prefix(lower)).trimmingCharacters(in: .whitespacesAndNewlines) + ellipsis
    }
}
```

- [ ] **Step 4: Fit task and project labels**

In `StatusItemMenuController`, define `private static let dynamicLabelWidth: CGFloat = 400`.

For project rows, measure the count suffix, fit only the project name to the remaining budget, build the native item with the fitted name, and set `item.toolTip = project.name`.

For task rows, preserve the priority dot and attributed metadata. Fit project metadata to 120 points, measure fixed dot/spacing/metadata width, and fit the task title into `max(120, dynamicLabelWidth - fixedWidth)`. Set `item.toolTip = task.title`.

- [ ] **Step 5: Run GREEN and full verification**

Run the focused suite, full macOS suite, signed Mac build, strict codesign, and `git diff --check`. Expected: 71 tests pass and all commands exit 0.

- [ ] **Step 6: Reinstall and measure the real menu**

Copy the signed build to `/Applications/ShipBar.app`, launch it, open the real status menu containing the reported podcast task, and capture the menu bounds. Confirm width is approximately 480 points, the long row has one ellipsis, short labels remain unchanged, project submenus/actions work, and hovering retains the full title.

- [ ] **Step 7: Review and commit**

Run an independent spec/code-quality review. Commit the utility, tests, controller integration, and generated project membership with:

```bash
git add Sources/Mac/StatusMenuTextFitter.swift \
  Sources/Mac/StatusItemMenuController.swift \
  Tests/ShipBarTests/StatusMenuTextFitterTests.swift \
  project.yml ShipBar.xcodeproj/project.pbxproj
git commit -m "fix: keep the status menu compact"
```

