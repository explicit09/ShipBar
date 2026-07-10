# Task 4: Graphite + Signal and Accessibility

## Outcome

Applied the approved Graphite + signal presentation pass without changing persistence or workflow behavior:

- Shared glass, command-strip, dock, focus-row, task-row, and run-row surfaces now use the established Graphite tokens and radius hierarchy.
- Selected surfaces use restrained ship blue; waiting/review attention stays amber; failed runs stay red and retain textual status.
- Command-strip and dock controls are explicitly keyboard focusable. Page titles are headings, dock controls announce destination plus actionable count (including zero), task actions have complete labels, and run rows retain task/status/agent text.
- The dock measures its container, stays full-width at 420 points, and is centered/capped at 520 points in wide windows.
- iPhone capture, inbox summary, project, and new-project actions retain at least 44-point targets; native `TabView` remains unchanged. iPhone run rows now show and announce the agent, and failed runs use red independently of section tint.

## Review correction

The first Task 4 review found the adaptive outline contract was duplicated and had missed Flight Plan and both Settings cards. The correction centralizes color-scheme contrast handling in `ShipBarAdaptiveOutline` / `shipBarOutline`:

- Shared glass, command strip, dock, focus rows, task rows, and run rows now route outline width/color through the same modifier.
- Flight Plan uses `pageRadius` and a semantic blue outline that changes from one to two points under Increased Contrast.
- Settings diagnostic and action cards use `rowRadius` plus the same adaptive outline contract.
- Selected outlines remain ship blue, failed-run outlines remain red, and ordinary Graphite outlines use shared normal/increased stroke tokens.
- Each dock destination captures its actionable count once so its visible badge and accessibility label cannot diverge during a render.

## TDD evidence

- RED 1: eight focused source-contract checks failed before implementation for missing focusability, combined dock counts, radius tokens, iOS agent labels, and the 44-point capture target (exit 1, eight expected failures).
- GREEN 1: all eight checks passed after the minimal implementation.
- RED 2: signed wide-window inspection showed the first flexible-frame cap still stretched the dock. A measured-width contract failed before the correction (exit 1).
- GREEN 2: the measured-width contract passed after using `min(proxy.size.width, 520)`; the rebuilt signed app then showed the dock centered and capped in the maximized window.
- RED 3: self-review found the shared selected-surface stroke color was defined but its line width was still forced to zero. The contrast-outline contract failed (exit 1).
- GREEN 3: selected and unselected shared surfaces now use one point normally and two points under Increased Contrast.
- Review-fix RED: five shared-contract checks failed for the missing modifier, duplicated environment ownership, Flight Plan, Settings cards, and dock count reuse.
- Review-fix GREEN: all five checks passed after the coherent shared-contract migration.

## Automated verification

- `xcodegen generate`: exit 0.
- Full `ShipBarTests`: 62 passed, 0 failed, 0 skipped.
- `ShipBarMac` signed build: exit 0.
- `codesign --verify --deep --strict --verbose=2`: valid on disk and satisfies its Designated Requirement.
- `git diff --check`: exit 0.
- iOS compile attempt: blocked before compilation because iOS 26.4 is not installed; Xcode exposed only an ineligible generic iOS destination.

## Signed runtime review

Computer Use inspected the signed Mac app at 420 x 620 in the current dark appearance and in a maximized wide window:

- Compact Today preserved the Flight Plan anchor, five named dock destinations, 44-point dock controls, restrained blue selection, amber review badges, readable state labels, and independent content scrolling.
- Wide Today gained whitespace while the dock stayed centered at roughly 520 points rather than stretching.
- Runs exposed Needs Review, Active, Recent, and failed rows. The accessibility tree announced task, textual status, and Codex for every run; failure was visibly red.
- Inbox retained its hierarchy and fixed dock with readable Graphite rows.
- The accessibility tree announced Search and Global capture with hints; all five destinations included counts, including `Projects, 0 actionable` and `Settings, 0 actionable`; focus rows retained position, Working now, Up next, and Waiting text.
- Keyboard focus was AX-reported on Search and rendered with a visible blue focus outline. Command-2 and Command-3 navigation remained functional.

## Accessibility proof boundary

- Reduced Motion is preserved by `ShipBarRootView` clearing transaction animation when `accessibilityReduceMotion` is enabled; Task 4 did not alter that path.
- Increased Contrast is implemented through `colorSchemeContrast` with two-point outlines on the shared glass, command strip, dock, focus rows, task rows, and run rows.
- A post-review source audit confirms `ShipBarAdaptiveOutline` is the sole owner of `colorSchemeContrast` across the polished surface set; Flight Plan and both Settings cards now use it too.
- App-scoped light-mode launch arguments and `NSAppearance` environment overrides were ignored by AppKit on this machine. Light appearance was therefore not independently proven in the signed runtime. The adaptive surfaces use `Color.primary`/semantic colors rather than fixed dark fills, but that is code-path evidence, not a live light-mode pass.
- iPhone runtime verification remains blocked with the missing iOS 26.4 platform; hit-target and label results are compiler/source evidence.

## Self-review

- Diff is limited to eleven source files plus this report and its HTML companion. The nine brief-listed files are joined by the two required integration files, `ShipBarRootView.swift` and `TodayCommandCenterView.swift`.
- No actions, native tabs, persistence behavior, or accessibility labels were removed.
- The token names and requested opacity values remain stable.
- No ornamental decoration was added; the prior blue glow on the current-row mark was removed.
- The only unresolved verification concern is the unavailable live light/increased-contrast/reduced-motion/iPhone environment noted above.
- Task 5 was not started.
