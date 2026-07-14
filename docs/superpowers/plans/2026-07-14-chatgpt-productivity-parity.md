# ShipBar ChatGPT Productivity Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give ordinary ChatGPT complete, safe, offline-capable task and project management through ShipBar.

**Architecture:** A typed Supabase command queue carries mutations to the canonical local SwiftData store. The relay worker invokes closed `shipbarctl` commands, publishes task/project mirrors and tombstones, and returns truthful command lifecycle states to MCP tools.

**Tech Stack:** Swift 6, SwiftData, TypeScript 5.8, Vitest, Supabase Postgres/Edge Functions, MCP JSON-RPC, ChatGPT developer-mode plugin.

## Global Constraints

- ShipBar's local SwiftData store remains canonical.
- Queued never means applied.
- All writes are idempotent and revision-protected.
- Trash is recoverable; permanent deletion is allowed only from Trash.
- Create/edit/complete/move are low-risk; Trash, permanent delete, and Codex execution require explicit confirmation.

---

### Task 1: Local closed command surface

**Files:**
- Modify: `Sources/Shared/Bridge/ShipBarBridgeModels.swift`
- Modify: `Sources/CLI/ShipBarCLICore.swift`
- Modify: `Sources/Mac/Bridge/ShipBarBridgeProcessor.swift`
- Modify: `Sources/Shared/Models/ShipTask.swift`
- Modify: `Sources/Shared/Models/Project.swift`
- Test: `Tests/ShipBarTests/ShipBarCLIContractTests.swift`
- Test: `Tests/ShipBarTests/ShipBarBridgeProcessorTests.swift`

**Interfaces:**
- Produces: `apply-command --command <json>` returning a `ShipBarBridgeCommandResult` with `status`, `recordID`, `revision`, `summary`, and mirrors.
- Supports task/project create, update, focus, status, move, Trash, restore, and permanent delete.

- [ ] Write failing parser and processor tests for each command family, revision conflicts, Trash, restore, and permanent-delete refusal.
- [ ] Run `xcodebuild test -project ShipBar.xcodeproj -scheme ShipBarTests -destination 'platform=macOS'` and verify the new tests fail for missing `apply-command` behavior.
- [ ] Add revision and Trash metadata to models and implement the minimal closed command enum, parser, processor, and summaries.
- [ ] Run the focused suites and the full ShipBar test target; expect all tests to pass.
- [ ] Commit the local command surface.

### Task 2: Durable hosted command queue

**Files:**
- Create: `supabase/migrations/20260714170000_productivity_command_queue.sql`
- Modify: `supabase/functions/shipbar-relay/router.ts`
- Modify: `supabase/functions/shipbar-relay/repository.ts`
- Modify: `supabase/functions/shipbar-relay/router_test.ts`
- Modify: `supabase/functions/shipbar-relay/repository_test.ts`

**Interfaces:**
- Produces: `enqueueCommand`, `getCommand`, leased `commands` in pull, and `commandAcknowledgements` in push.
- Command states: `queued`, `claimed`, `applied`, `failed`, `conflicted`, `canceled`.

- [ ] Write failing Deno tests for idempotent enqueue, lease claim, status lookup, acknowledgement, and revision conflict reporting.
- [ ] Run `deno test --allow-env supabase/functions/shipbar-relay/*_test.ts` and verify the new tests fail for missing repository methods.
- [ ] Add the SQL queue/RPCs and implement repository/router behavior with owner isolation and safe summaries.
- [ ] Run relay tests and `supabase db lint`; expect success.
- [ ] Commit the hosted command queue.

### Task 3: Worker delivery and mirror parity

**Files:**
- Modify: `Integrations/shipbar-relay-worker/src/worker.ts`
- Modify: `Integrations/shipbar-relay-worker/src/client.ts`
- Modify: `Integrations/shipbar-relay-worker/test/worker.test.ts`
- Modify: `Integrations/shipbar-relay-worker/test/client.test.ts`

**Interfaces:**
- Consumes: pulled typed commands from Task 2 and `apply-command` from Task 1.
- Produces: task/project mirrors, tombstones, and terminal command acknowledgements.

- [ ] Write failing Vitest cases for apply, conflict, failure, offline retry, and task/project mirror acknowledgement.
- [ ] Run `npm test` in `Integrations/shipbar-relay-worker`; verify failures identify missing command handling.
- [ ] Add `applyCommand` to `ShipBarPort`, invoke `shipbarctl apply-command`, and push truthful acknowledgements.
- [ ] Run `npm test`, `npm run typecheck`, and `npm run build`; expect success.
- [ ] Commit worker delivery.

### Task 4: Complete MCP productivity tools

**Files:**
- Modify: `supabase/functions/shipbar-mcp/mcp.ts`
- Modify: `supabase/functions/shipbar-mcp/mcp_test.ts`

**Interfaces:**
- Produces reads: `list_tasks`, `get_task`, `list_projects`, `get_project`, `list_trash`, `get_command_status`.
- Produces writes: `create_task`, `update_task`, `create_project`, `update_project`, `trash_record`, `restore_record`, `permanently_delete_record`.
- Retains: Today, device, and execution tools.

- [ ] Write failing schema and call tests proving complete fields, read-before-write revisions, confirmation annotations, and truthful queued/applied wording.
- [ ] Run `deno test --allow-env supabase/functions/shipbar-mcp/mcp_test.ts`; verify the missing tools fail.
- [ ] Implement focused tool descriptors and repository calls; keep destructive annotations only on Trash/permanent delete and Codex execution.
- [ ] Run MCP and relay suites; expect all tests to pass.
- [ ] Commit MCP parity.

### Task 5: Deploy and live productivity probe

**Files:**
- Modify: `docs/reviews/2026-07-14-ios-testflight-verification.html`
- Create: `docs/reviews/2026-07-14-chatgpt-productivity-probe.html`

**Interfaces:**
- Consumes: deployed migration, relay, MCP, installed macOS app, and ChatGPT ShipBar plugin.
- Produces: live evidence for every read/write path and cleaned isolated fixtures.

- [ ] Run all Swift, Deno, and worker verification commands and record exact results.
- [ ] Deploy the migration and Edge Functions, rebuild/install ShipBar, restart the relay worker, and refresh the ChatGPT plugin.
- [ ] In normal ChatGPT, create `ChatGPT QA`, create a fully detailed task, inspect it, edit every field, move/focus/reorder/complete/reopen it, and verify the installed app after each command reaches `applied`.
- [ ] Exercise project/task Trash and restore. Ask for action-time approval before permanent deletion, then clean up the QA fixtures.
- [ ] Write the brief interactive HTML evidence report, commit all changes, and push the branch.

