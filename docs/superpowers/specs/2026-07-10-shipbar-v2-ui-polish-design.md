# ShipBar V2 UI Polish Design

**Date:** July 10, 2026  
**Status:** Approved for implementation planning

## Objective

Make ShipBar faster to understand and easier to navigate at its real 420 × 620 Mac window size without changing its V2 data model or weakening truthful agent-run behavior.

The approved direction is **Graphite + signal** with a fixed **bottom destination dock** and a slim **top command strip**.

## Design Principles

1. Destination names remain visible at compact width.
2. Workflow color communicates state, not decoration.
3. The current decision receives the strongest hierarchy.
4. Global actions remain available without displacing page content.
5. Keyboard, VoiceOver, increased contrast, and reduced motion remain first-class.

## Navigation

### Top Command Strip

The fixed command strip contains:

- A Command–K search affordance labeled “Search ShipBar.”
- A global capture button that opens the existing capture flow.
- Keyboard focus and VoiceOver labels for both actions.

The strip is intentionally slim. It does not duplicate destination navigation.

### Bottom Destination Dock

The fixed dock contains five equal-width destinations:

1. Today
2. Inbox
3. Runs
4. Projects
5. Settings

Each destination always shows an icon and label. The selected destination uses a quiet blue surface and stronger foreground. Counts appear only when actionable:

- Today: open Now, Next, and Waiting work.
- Inbox: untriaged items.
- Runs: Needs Review plus failures requiring attention.

Keyboard shortcuts `Command–1` through `Command–5` navigate the same destinations. Content scrolls independently between the command strip and dock.

The iPhone target keeps native `TabView` navigation while sharing the same labels and workflow colors.

## Visual System: Graphite + Signal

ShipBar uses layered graphite surfaces with restrained borders and native typography.

- Ship blue: focus, selection, Today, and navigation.
- Review amber: waiting and Needs Review.
- Run purple: prepared, handed-off, and running agent work.
- Success green: accepted and completed work.
- Red: failure and destructive actions only.

Cards use one consistent radius family, subtle one-pixel outlines, and small depth changes. Increased Contrast strengthens outlines. Reduced Motion removes nonessential transitions.

## Shared Components

Three reusable presentation components establish consistency without changing persistence:

- `ShipBarCommandStrip`: global search and capture.
- `ShipBarDestinationDock`: destination selection, labels, badges, and shortcuts.
- `ShipBarPageHeader`: title, concise purpose, and optional primary action.

`ShipBarRootView` owns navigation state and composes these components around existing destination content. Task, project, focus, and run lifecycle APIs remain unchanged.

## Destination Hierarchy

### Today

- Page header retains date, current target, and completion ring.
- Flight Plan remains the signature visual anchor.
- Now is the strongest task card.
- Next, Waiting, and Completed use progressively quieter hierarchy.
- Add, remove, reorder, complete, and open-task behavior remain unchanged.

### Inbox

- Header appears before capture and explains that Inbox is a triage queue.
- Capture uses compact copy that does not truncate at 420 points.
- Rows retain selection, task detail, and per-item triage.
- The batch action bar stays pinned above the dock while selection is active.
- Escape continues to clear selection.

### Runs

- Header exposes the review promise: delegate work, keep the decision.
- Needs Review appears first and strongest.
- Active and Recent remain visually separate.
- Every state retains a text label in addition to color.
- Review, evidence, Accept, Request Changes, failure, and cancellation remain unchanged.

### Projects

- Project list gains a page header and visible New Project action.
- Each project row shows open work and a compact progress cue.
- Workspace retains outcome, repo, prompt, health metrics, scoped capture, tasks, and recent runs.
- Back-to-projects navigation is explicit inside the content header.

### Settings

- Diagnostics and actions become grouped cards.
- CloudKit, Share Extension, and local-save truth labels remain unchanged.
- Preview mode continues to state that CloudKit is disabled and the store is isolated.

## Accessibility and Error Behavior

- All dock and command-strip controls have combined labels and minimum hit areas.
- Keyboard focus is visible on navigation and primary actions.
- State meaning never depends on color alone.
- Dynamic Type-safe iPhone layouts and 44-point actions are preserved.
- Destructive actions retain confirmation.
- Empty states include a next action rather than only describing absence.
- If capture or persistence fails, existing persistence diagnostics remain the source of truth.

## Verification Scope

The polish is complete only after verifying:

- Automated model, query, lifecycle, capture, sync, command-search, and preview-fixture tests.
- Signed Mac build.
- Today focus add, remove, reorder, complete, Waiting, and Completed.
- Global capture and Command–K navigation/search.
- Inbox item selection, Escape, project assignment, Today, Someday, and confirmed delete presentation.
- Task detail editing and agent handoff preparation.
- Runs queues, evidence editing, review decisions, failure, and cancellation presentation.
- Project creation entry point, project workspace editing, health, and recent runs.
- Settings diagnostics and preview truth labels.
- Empty and populated states at 420 × 620 and a wider resized window.
- Keyboard navigation, accessibility labels, Increased Contrast, and Reduced Motion behavior.

ShipBar is a native SwiftUI application, so browser-only Playwright QA is not used for product interaction. Native unit tests and Computer Use against the signed app provide the runtime evidence.

## Out of Scope

- New persistence fields or migrations.
- New agent providers or external-agent completion detection.
- Replacing native iPhone tab navigation.
- Installing the missing iOS 26.4 Xcode platform component.
- Marketing pages or a public redesign.

## Acceptance Criteria

- All five Mac destinations remain named and reachable at 420 points wide.
- Global search and capture are visible from every destination.
- The current page and its primary action are clear without reading documentation.
- Existing V2 behavior and stored data remain intact.
- Signed Mac runtime inspection finds no navigation, clipping, focus, or state-label regressions.
- Automated tests and the signed Mac build pass.
- iOS verification remains explicitly blocked until the local Xcode iOS platform is installed.
