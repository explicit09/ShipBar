# ShipBar V1 Design

Date: 2026-05-16

## Summary

ShipBar is a small native Apple utility for keeping a personal execution queue for AI-assisted building. It is not a web app and not a general notes app. V1 focuses on a macOS menu bar app plus an iPhone SwiftUI app target, both using the same SwiftData model and syncing through the user's private iCloud account with CloudKit.

The product question ShipBar answers is: "What do I need to build next, and what prompt should I give the AI agent?"

## Goals

- Provide an always-available macOS menu bar interface for projects, tasks, and prompts.
- Provide an iPhone app target from the start using the same model and core screens.
- Store data locally first and sync through CloudKit private database.
- Make quick capture fast enough that the user does not avoid writing tasks down.
- Keep AI prompts first-class but optional.
- Use a polished CodexBar-inspired Mac panel style without inheriting CodexBar's provider-tracking complexity.

## Non-Goals

- No web app.
- No Supabase or custom backend.
- No team sharing.
- No GitHub issue export in V1.
- No direct Codex, Claude Code, or Cursor dispatch in V1.
- No recurring reminders or scheduling engine.
- No AI-generated prompt rewriting in V1.
- No full project management system, kanban board, or calendar.

## Platform Direction

ShipBar V1 uses a native Swift codebase with shared SwiftUI views where practical.

The macOS app uses AppKit for the menu bar shell:

- `NSStatusItem` owns the top menu bar icon.
- A SwiftUI-hosted panel or popover renders the ShipBar content.
- The app should feel like a compact menu bar utility, not a Dock-first desktop app.

The iPhone app uses standard SwiftUI navigation:

- Today view.
- Project list.
- Task detail/edit view.
- Quick capture.

Both platforms use the same persistence layer and core model types.

## Sync

V1 uses SwiftData with CloudKit private database sync.

Expected behavior:

- Local writes are immediate.
- Cross-device sync is near-realtime when devices are online and awake, but not guaranteed realtime.
- On app launch, app foregrounding, or Mac panel open, ShipBar should refresh from local state and allow CloudKit to pull remote changes.
- The app should not present CloudKit sync as live collaboration.

CloudKit is chosen because ShipBar is Apple-only and personal. It avoids a separate account system and keeps the data in the user's iCloud account.

## Data Model

### Project

Fields:

- `id`
- `name`
- `color`
- `icon`
- `sortOrder`
- `createdAt`
- `updatedAt`

Rules:

- A task belongs to one project.
- Projects are shown in user-defined order.
- V1 can seed example project names only if useful during development; shipped builds should allow an empty state.

### ShipTask

Fields:

- `id`
- `project`
- `title`
- `description`
- `prompt`
- `status`: `todo`, `doing`, `done`
- `priority`: `low`, `medium`, `high`
- `type`: `feature`, `bug`, `chore`, `idea`
- `createdAt`
- `updatedAt`
- `completedAt`

Rules:

- `title` is required.
- `prompt` is optional.
- `description` is optional.
- `completedAt` is set when status becomes `done` and cleared when moved out of `done`.
- Default status is `todo`.
- Default priority is `medium`.
- Default type is `idea` unless parsed or selected.

## Mac UX

The macOS experience is inspired by CodexBar's compact, polished menu bar card:

- Compact translucent panel.
- Top tab/switcher row.
- Dense task rows with strong scanability.
- Quick actions near task rows and panel footer.
- No visual clutter beyond what helps capture and shipping.

Top switcher:

- `Today`
- One item per project, limited by available width.
- `+` for new project or task entry point.

Today view:

- Shows open tasks across projects.
- Sorts high priority first, then newest or user order.
- Each row shows completion checkbox, title, project, type, priority, and prompt-ready state.

Project view:

- Shows open tasks for the selected project.
- Allows switching between `todo`, `doing`, and `done` where space allows.

Quick capture:

- Available directly in the panel.
- Accepts plain text.
- Accepts simple prefix syntax.
- If parsing fails, saves the whole input as the title.

Task detail:

- Opens inside the panel or a compact auxiliary editor.
- Edits title, project, status, priority, type, description, and prompt.
- Includes `Copy Prompt` when prompt is non-empty.
- Includes mark done/reopen.

Panel footer:

- `New Task`
- `New Project`
- `Settings`
- `Quit`

## iPhone UX

The iPhone app is simple and native:

- A Today screen for open tasks.
- A Projects screen.
- Task detail/edit screen.
- Quick capture button or input.
- Copy prompt action from task detail.

The iPhone app does not need to mimic the Mac panel visually. It should use standard SwiftUI patterns while keeping the same information hierarchy.

## Prefix Capture

Prefix parsing is a convenience layer, not a strict command language.

Example:

```text
vedit high feature: Add undo stack
```

Expected parse:

- Project: `vedit`
- Priority: `high`
- Type: `feature`
- Title: `Add undo stack`

Parsing rules:

- Match a project token by case-insensitive project name or slug.
- Match priority tokens: `low`, `medium`, `med`, `high`.
- Match type tokens: `feature`, `bug`, `chore`, `idea`.
- A colon separates metadata tokens from the title when present.
- If no colon is present, parse leading known tokens and treat the rest as title.
- If there is not enough confidence, keep the entire input as the title.
- Parsing must never block saving.

## AI Prompt Workflow

Prompts are optional but first-class.

V1 supports:

- Prompt field on task detail.
- Visual indicator when a task has a prompt.
- Copy prompt action.

V1 does not support:

- Sending prompt to Codex or Claude Code.
- Opening a repo automatically.
- Creating GitHub issues.
- Tracking agent runs.

The design leaves room for later `AgentRun` records, but they are not part of the V1 schema.

## Architecture

Suggested module boundaries:

- `ShipBarApp`: SwiftUI app entry points and platform-specific scene setup.
- `MenuBar`: macOS `NSStatusItem` controller and SwiftUI panel hosting.
- `Models`: SwiftData entities and enums.
- `Data`: model container setup, CloudKit configuration, sample data utilities for debug builds.
- `Features/Capture`: prefix parser and capture flow.
- `Features/Tasks`: task list, filters, rows, and detail editor.
- `Features/Projects`: project list, project editor, and switcher model.
- `SharedUI`: reusable cross-platform controls.

The parser should be independent of SwiftUI so it can be unit tested directly.

## Error Handling

- Empty capture input should not create a task.
- CloudKit availability issues should not block local capture.
- Sync errors should surface quietly in settings or a small status line, not as modal interruptions.
- Copy prompt should be disabled or hidden when no prompt exists.
- Deleting a project with tasks should require confirmation or be deferred out of V1.

## Testing

V1 should include focused tests for:

- Prefix parser behavior.
- Default task values.
- Status transition behavior for `completedAt`.
- Today/project filtering.
- Sorting by priority.

UI testing can stay light in V1:

- macOS panel opens and renders an empty state or seeded debug state.
- iPhone Today view renders.

## Acceptance Criteria

- The macOS app launches as a menu bar utility.
- The user can create, edit, complete, and reopen tasks.
- The user can create projects and assign tasks to projects.
- The user can capture a task from one line of text.
- The user can use prefix syntax for project, priority, and type.
- The user can add and copy an optional AI prompt.
- The iPhone target can view and edit the same model.
- Data persists locally and is configured for CloudKit sync.

