# ShipBar V2 final review fixes

**Base:** `335721e`

**Date:** 2026-07-10

**Result:** All 3 Important and all 3 Minor findings addressed on macOS; iOS remains blocked before compilation because Xcode lacks iOS 26.4.

## Fixes

- `ProjectWorkspaceView` keeps the explicit `backToProjects` closure and exposes its labeled in-content button only on macOS. Every root integration clears `selectedProjectID`; iOS retains its existing toolbar back action without duplication.
- The dock preserves optional counts, omits count language for Projects/Settings, and resets then conditionally adds `.isSelected` so only the current destination is selected in the live AX tree.
- Shared Settings action labels fill the available width with a 44-point minimum height and rectangular content shape. Mac Settings content is unchanged.
- Task 4 now states the correct eleven-source-file scope and names `ShipBarRootView.swift` and `TodayCommandCenterView.swift` as integration files.
- The canonical QA HTML links retained compact/wide screenshots encoded as genuine PNGs, representative AX text, and a command/exit summary.
- README preview commands use explicit `${TMPDIR%/}/ShipBarDerivedData`, avoiding both Xcode's machine-specific hash and FileProvider signing attributes on repo-local build output.

## TDD evidence

- Initial focused run: exit 65; 4 tests reported 10 expected missing-contract issues.
- Portable-path refinement: exit 65 before replacing repo-local DerivedData.
- Selected-trait reset refinement: exit 65 after signed runtime exposed a stale Today trait.
- Focused final-review contracts: exit 0.
- Minor cleanup guard refinement: exit 65 before the macOS platform guard, then exit 0 after implementation.

## Final verification

- `xcodegen generate`: exit 0.
- Full `ShipBarTests`: exit 0; 66 passed, 0 failed, 0 skipped on macOS 26.3.1.
- Signed `ShipBarMac` build with explicit DerivedData path: exit 0.
- `codesign --verify --deep --strict`: exit 0; valid on disk, team `5986DKD528`.
- Signed runtime: Back to Projects passed at 420 × 620 and 1224 × 768; only the active dock destination was selected; Projects/Settings omitted counts; Mac Settings retained its three diagnostics and two actions.
- `file` identifies both retained screenshots as genuine PNG images; `sips` confirms their dimensions remain 420 × 620 and 1224 × 768.
- iOS simulator attempt: exit 70 before compilation because `iOS 26.4 is not installed`. The 44-point shared Settings contract is source/test evidence pending platform installation.
- No destructive UI action was opened or confirmed. Preview mode used the isolated in-memory store and the preview environment was unset after launch.

## Inspectable evidence

- [Canonical QA HTML](../../docs/reviews/2026-07-10-shipbar-v2-ui-polish-qa.html)
- [Compact screenshot](../../docs/reviews/2026-07-10-shipbar-v2-ui-polish-qa-evidence/compact-project-workspace.png)
- [Wide screenshot](../../docs/reviews/2026-07-10-shipbar-v2-ui-polish-qa-evidence/wide-project-workspace.png)
- [Representative AX text](../../docs/reviews/2026-07-10-shipbar-v2-ui-polish-qa-evidence/accessibility.txt)
- [Command and exit summary](../../docs/reviews/2026-07-10-shipbar-v2-ui-polish-qa-evidence/commands.txt)

## Remaining blocker

Install Xcode's iOS 26.4 platform, then rerun the documented simulator build and inspect the shared Settings rows on iPhone. This is an environment blocker, not a passing or failing iOS result.
