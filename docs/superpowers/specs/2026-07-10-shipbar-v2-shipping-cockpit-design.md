# ShipBar V2 Shipping Cockpit Design

Date: 2026-07-10
Status: Proposed for implementation

## Summary

ShipBar V2 turns the existing personal task queue into a local-first shipping cockpit for one builder working with AI coding agents. It preserves the speed and calm of a native task manager while making the complete loop visible: capture work, choose what matters today, delegate it, monitor the handoff, review evidence, and close the task.

V2 is not a team issue tracker, an AI chat client, or a replacement for Codex, Claude Code, Cursor, or GitHub. ShipBar remains the small control surface that coordinates those tools.

## Product Promise

> Know what to ship next, send it to the right agent, and never lose track of the result.

ShipBar should feel faster than opening a project manager, calmer than an AI dashboard, and more accountable than copying prompts between tools.

## Competitive Bar

V2 adapts four transferable ideas without copying competitor branding or expanding into their full scope:

- Things: immediate capture, calm hierarchy, progressive disclosure, and keyboard-first navigation.
- Superlist: tasks, notes, and voice in one coherent object with expressive but restrained presentation.
- Linear: agent delegation remains attached to a human-owned task and agent activity is visible.
- Raycast: a command surface is always one shortcut away and actions are discoverable without leaving the keyboard.

ShipBar differentiates through a narrower end-to-end workflow for solo builders: source-aware capture, daily focus, repo-aware agent handoff, local run history, evidence review, and completion.

## Goals

- Make the next shippable action obvious within three seconds of opening ShipBar.
- Capture a task from any Mac app in under two seconds once the shortcut is learned.
- Delegate a prepared task to an agent in one explicit action.
- Show which work is waiting on the user, waiting on an agent, blocked, or complete.
- Keep task ownership with the user even when work is delegated.
- Preserve local-first behavior and graceful operation without CloudKit, an API key, or an agent integration.
- Deliver a coherent Mac command center and a focused iPhone companion using shared models and workflow rules.
- Give ShipBar a distinctive, premium native identity without sacrificing density or accessibility.

## Non-Goals

- Team accounts, permissions, comments, or shared workspaces.
- A general-purpose document editor or knowledge base.
- Hosting or executing coding agents inside ShipBar.
- Pretending clipboard handoffs provide live agent telemetry.
- A kanban board, Gantt chart, calendar replacement, or sprint-management system.
- Automatic GitHub mutations in the first V2 release.
- A web application or non-Apple client.

## Core Workflow

1. **Capture** — The user records an idea through the global text panel, voice, share extension, or the main window. Source app, source URL, raw capture text, project, priority, type, and due intent are preserved when available.
2. **Triage** — Inbox items are assigned to a project, clarified, scheduled, or discarded. A task can remain lightweight until it becomes actionable.
3. **Focus** — Up to three tasks can be selected for today's focus. The command center separates Now, Next, Waiting, and Completed Today.
4. **Prepare** — A task gains a useful prompt, repository path, acceptance notes, and optional context before delegation.
5. **Delegate** — ShipBar snapshots the handoff into an `AgentRun`, copies the composed prompt, opens the target agent at the repository when possible, and marks the run as handed off.
6. **Track** — The user can mark the run running, needing review, completed, failed, or canceled. V2 displays truthful local state and never implies external telemetry it does not possess.
7. **Review** — The run can hold a result summary and evidence links such as a local report, commit, branch, or pull request URL. “Needs Review” becomes a first-class queue.
8. **Close** — Accepting a successful run can complete the task. Rejected or failed results return the task to an actionable state while keeping history.

## Information Architecture

### Mac Main Window

The Mac window remains compact, resizable, and useful at its default 420×620 size. Its primary destinations are:

- **Today** — Daily command center and default destination.
- **Inbox** — Fast triage queue.
- **Runs** — Active, review-ready, and recent agent handoffs.
- **Projects** — Project health and workspaces.
- **Settings** — Capture, agent, sync, appearance, and data diagnostics.

The destination bar uses icons plus labels at comfortable widths and collapses labels only when required. Counts appear only when actionable: Inbox, Needs Review, and active failures.

### Today

Today is not a flat due-date list. It contains:

- A compact day header with greeting-free product language, date, completion ring, and a single primary capture button.
- **Top 3** focus slots. Empty slots teach the gesture; populated slots support reorder and removal.
- **Now** for the first incomplete focus task.
- **Next** for remaining focused and due-today work.
- **Waiting** for tasks with active or review-ready agent runs.
- **Completed Today** collapsed by default with a visible count.

When there is no work, the screen shows one useful action instead of a decorative empty state.

### Inbox

Inbox optimizes repeated triage:

- Each row exposes project, schedule, priority, and type through one contextual action surface.
- Keyboard triage supports next/previous selection, project assignment, Today, Someday, and delete.
- Multi-select and batch actions are included for project assignment, scheduling, and deletion.
- Source context is visible but secondary.

### Runs

Runs is divided into:

- **Needs Review** — completed or paused work requiring the user's decision.
- **Active** — prepared, handed off, or marked running.
- **Recent** — completed, failed, or canceled history.

Each run row shows task, project, target agent, truthful local state, elapsed or completed time, and evidence availability. Selecting a run opens a review surface with the prompt snapshot, notes, result summary, evidence links, and Accept / Request Changes / Mark Failed actions.

### Projects

The project list shows name, color, open task count, focus count, active run count, and progress. A project workspace contains:

- Outcome header and editable repository path.
- Progress and current focus.
- Open tasks grouped by actionable state rather than only raw status.
- Recent runs and completed work.
- Quick capture already scoped to the project.

### iPhone

iPhone is a companion, not a compressed Mac dashboard. It provides:

- Today with Top 3, Waiting, and completion progress.
- Inbox triage with native swipe actions.
- Runs review with links and decisions.
- Projects and task detail.
- Text and voice capture.

Agent launching remains available only when the target has a valid iOS behavior; otherwise iPhone prepares the run and clearly labels it “Ready to hand off on Mac.”

## Universal Command Surface

The existing global capture shortcuts remain:

- Command–Shift–K: text capture.
- Command–Shift–V: voice capture.

Inside the main window, Command–K opens a universal command surface for navigation, search, capture, and actions. It supports:

- Fuzzy task and project search.
- Jump to Today, Inbox, Runs, Projects, or Settings.
- Create task or project.
- Set focus, triage, change status, or delegate the selected task.
- Open recent tasks and runs.

Commands are grouped, keyboard navigable, and display shortcuts. Destructive actions require an explicit confirmation.

## Task and Run Model

### ShipTask additions

- `focusDate: Date?` — calendar day for which the task is focused.
- `focusOrder: Int?` — stable order from one through three.
- `reviewStateRawValue: String?` — optional cached presentation state when useful for migration and query simplicity.

Focus invariants:

- At most three incomplete tasks have today's `focusDate`.
- Focus order is unique and compacted after removal.
- Completing a focused task preserves its completion history but frees the Now position.
- Moving a task to another day clears or updates its focus assignment explicitly.

### AgentRun

`AgentRun` is a new SwiftData model. CloudKit-compatible fields have defaults or are optional.

- `id: String`
- `taskID: String`
- `projectID: String?`
- `taskTitleSnapshot: String`
- `projectNameSnapshot: String?`
- `targetRawValue: String`
- `statusRawValue: String`
- `promptSnapshot: String`
- `repositoryPathSnapshot: String`
- `createdAt: Date`
- `updatedAt: Date`
- `startedAt: Date?`
- `finishedAt: Date?`
- `resultSummary: String`
- `evidenceURLString: String`
- `errorMessage: String`

Run states are `prepared`, `handedOff`, `running`, `needsReview`, `completed`, `failed`, and `canceled`.

Allowed transitions are explicit and tested. History is append-only except for user-entered review metadata and state transitions. A deleted task does not erase its run history; snapshots keep the record intelligible.

### Truth Boundary

V2 distinguishes three sources of state:

- **Observed by ShipBar** — task changes, prompt copy, target launch, local timestamps, and user decisions.
- **Reported by the user** — running, result summary, evidence, failure, and completion.
- **Imported later** — future connector telemetry, which is outside this release unless a reliable local integration already exists.

The UI never labels a clipboard handoff as remotely running or complete without evidence.

## Visual System

ShipBar uses a dark-first, system-adaptive native surface with a calm industrial character.

- Accent: electric ship blue for navigation and primary actions.
- Success: restrained green for prompts ready, verified evidence, and completion.
- Attention: amber for inbox, due today, and needs review.
- Failure: red only for actionable errors and failed runs.
- Typography: system type with a strong 22-point page title, 13–14-point task content, and 11–12-point metadata.
- Surfaces: material background, low-contrast section panels, hairline separators, and limited shadows.
- Shape: 8–12-point radii for containers; capsules only for compact states and filters.
- Motion: short state transitions, row insertion/removal, focus reorder, and detail expansion. No decorative looping animation.

Task rows show title and one meaningful status line by default. Priority, source, prompt, and agent history become contextual indicators rather than a permanent chain of metadata.

Hover reveals secondary actions on Mac. Focus, selected, waiting, review, overdue, and completed states remain distinguishable without relying on color alone.

## Interaction and Accessibility

- Full keyboard traversal for destination bar, lists, command surface, menus, and review decisions.
- Visible focus rings and predictable arrow-key behavior.
- Minimum 44-point iOS targets and comfortable Mac hit areas.
- VoiceOver labels describe task state and actions without reading decorative symbols.
- Reduce Motion replaces animated reordering with immediate state changes.
- Increased Contrast strengthens separators, selection, and state outlines.
- Dynamic Type is respected on iPhone; Mac text remains legible at default density.
- Every color-coded state includes an icon, label, or structural cue.

## Architecture

New boundaries:

- `Models/AgentRun.swift` — persistent run model and state enum.
- `Tasks/FocusCoordinator.swift` — Top 3 invariants and ordering.
- `Tasks/AgentRunLifecycle.swift` — run creation, transitions, review decisions, and task reconciliation.
- `Views/Today/` — command-center sections and progress components.
- `Views/Runs/` — run list, row, and review surface.
- `Views/CommandBar/` — search index, commands, and presentation.
- `Views/Components/` — shared task row, state badge, progress, and empty-state primitives.

Existing mutation paths remain authoritative. The new coordinators call `ShipBarPersistence.save` and post existing notifications where appropriate. UI views do not duplicate lifecycle rules.

The first implementation pass may keep files in the existing folder structure if moving them would create unnecessary project-file churn, but responsibilities remain separated as described.

## Data Flow

### Delegation

1. The user chooses an agent target.
2. `PromptComposer` builds the handoff text.
3. `AgentRunLifecycle.prepare` snapshots the task, prompt, project, and repository.
4. The run is saved before any external launch.
5. The clipboard is updated and `AgentLauncher` opens the target.
6. On successful local launch request, the run becomes `handedOff`; on failure it remains `prepared` with an error.
7. The task and run surfaces update through SwiftData queries.

### Review

1. A run enters `needsReview` through a user action or future trusted import.
2. The user reads summary and evidence.
3. Accept marks the run complete and optionally completes the task in one transaction.
4. Request Changes creates a new prepared run from the existing task while retaining history.
5. Failure records the error and returns the task to an actionable queue.

## Sync and Migration

- Existing projects and tasks migrate in place; new task properties are optional.
- Existing `lastAgentTarget` and `lastAgentHandoffAt` values remain valid. They are not backfilled into synthetic runs because that would invent missing prompt and outcome history.
- `AgentRun` uses snapshot IDs rather than required relationships so task deletion and CloudKit ordering do not corrupt history.
- Signed builds continue to use CloudKit when entitlements are valid; unsigned and test builds use the established local fallback.
- Duplicate-resolution and deletion-log behavior must be extended only when required by observed sync behavior, not preemptively rewritten.

## Error Handling

- Capture and local task edits remain available when CloudKit, voice, or agent launching fails.
- Failed persistence logs the operation and shows a nonmodal recovery message when user action is required.
- Agent launch failure keeps the prepared run and offers Copy Again / Choose Another Agent.
- Missing repository paths warn before launch but allow prompt copy.
- Invalid evidence links remain editable and never block review decisions.
- Deleted or missing tasks render from the run snapshot.
- Empty, stale, and corrupted raw enum values fall back to safe display states.

## Verification

### Unit tests

- Top 3 insertion, reorder, removal, day rollover, and completion.
- Every allowed and rejected run-state transition.
- Run snapshot persistence when a task changes or is deleted.
- Accept, request-changes, fail, and cancel reconciliation.
- Today grouping and counts.
- Command search ranking and action availability.
- Migration with existing V1 task data.

### Integration tests

- Capture → triage → focus → prepare → handoff → review → complete.
- Relaunch persistence for focus and runs.
- Local fallback and CloudKit-entitled container creation.
- iPhone “Ready on Mac” behavior.

### Runtime review

- Build and run the signed Mac app.
- Inspect default, empty, populated, active-run, needs-review, failure, and completed states with Computer Use.
- Build an iPhone simulator target and inspect Today, Inbox, Runs, and task detail.
- Verify keyboard-only capture, navigation, focus selection, delegation, and review.
- Verify VoiceOver labels and Reduce Motion behavior for the main workflow.

## Delivery Slices

V2 is implemented as one release direction but verified in thin slices:

1. Models, migration, focus coordinator, and run lifecycle.
2. Mac Today command center and shared task-row system.
3. Runs list and review workflow.
4. Universal command surface and keyboard navigation.
5. Project workspace and Inbox triage upgrades.
6. iPhone Today, Runs, and review companion.
7. Visual polish, accessibility, state fixtures, and end-to-end verification.

Each slice must keep the project building and preserve existing capture, sync, task editing, and handoff behavior.

## Acceptance Criteria

- The user can choose and reorder up to three focus tasks for today.
- Today clearly separates current, next, waiting, and completed work.
- Every new agent handoff creates a durable run before launching the external tool.
- Run state is truthful, reviewable, and retained after task deletion.
- The user can accept results, request changes, record failure, or cancel a run.
- The Mac command surface can navigate, find, capture, focus, triage, and delegate without a mouse.
- Inbox supports fast single-item and batch triage.
- Project workspaces show progress, current focus, and agent activity.
- iPhone can review focus, triage Inbox, inspect runs, and prepare Mac handoffs.
- Existing V1 data migrates without loss.
- Capture, task editing, CloudKit fallback, voice, and existing handoff targets continue to work.
- Mac and iPhone builds pass, focused tests pass, and the primary workflow is inspected in the running apps.

