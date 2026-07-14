# ShipBar ChatGPT Productivity Parity Design

## Goal

Make the ShipBar app usable from an ordinary ChatGPT conversation for complete personal task and project management, while ShipBar remains local-first and commands remain safe when every device is offline.

## Architecture

Add a typed, durable command queue beside the existing capture and execution queues. ChatGPT's MCP tools enqueue commands in Supabase. The relay worker claims commands for a chosen ShipBar device, invokes closed `shipbarctl` commands against the real SwiftData store, and reports a terminal `applied`, `failed`, or `conflicted` result. Task and project mirrors let ChatGPT read before writing and prevent stale edits.

The local ShipBar database remains canonical. A queued response proves durable acceptance only. ChatGPT may claim a change happened only after the command reaches `applied`.

## Capabilities

### Reads

- Search and filter tasks, including Inbox, project, status, priority, type, due date, Today, and Trash.
- Inspect one task with every editable field and its current revision.
- List and inspect projects, including Trash.
- Inspect Today ordering, registered devices, command status, and Codex execution status.

### Task mutations

- Create a task with title, description, agent prompt, project, status, priority, type, due date, source metadata, and optional Today placement.
- Update any editable field without erasing unspecified fields.
- Move a task between Inbox and projects.
- Add, remove, and reorder Today.
- Mark doing, done, or reopen.
- Move to Trash, restore to its prior location, or permanently delete from Trash.

### Project mutations

- Create and update name, outcome, base prompt, repository path, color, icon, and ordering.
- Move to Trash after choosing whether its tasks move to Inbox or enter Trash with it.
- Restore a trashed project and its retained task relationships.
- Permanently delete only from Trash.

### Codex execution

- List devices before execution.
- Require explicit approval of task, device, repository, and instructions.
- Report queued, claimed, running, needs-review, completed, failed, or canceled truthfully.

## Tool guidance

- `description` contains task context and acceptance details for the human.
- `prompt` contains instructions an execution agent should follow.
- `project.outcome` defines the project's successful end state.
- `project.basePrompt` contains instructions inherited by project work.
- `project.repoPath` is optional for planning and required for Codex execution.
- ChatGPT asks only when ambiguity materially changes the result: an unknown project, an unclear date/timezone, conflicting records, or a destructive choice.
- Ordinary create, edit, move, focus, and completion actions can run immediately.
- Trash, permanent delete, and Codex execution require explicit confirmation.

## Safety and conflicts

Every mutation includes an idempotency key. Updates and destructive commands include the last observed revision. A revision mismatch yields `conflicted`; the client must reread and ask or retry deliberately. Trash is recoverable. Permanent deletion is refused unless the record is already in Trash. Project trash requires `move_tasks_to_inbox` or `trash_tasks` explicitly.

## Offline behavior

Commands remain queued until an eligible device claims them. One device applies each leased command. Expired leases are reclaimable. Command acknowledgements contain the local record ID, new revision, result summary, and safe mirror payload. The worker continuously publishes task and project mirrors plus tombstones so ChatGPT reads current state.

## Verification

Automated tests cover schemas, idempotency, leases, revisions, mutation behavior, Trash/restore/permanent delete, project task handling, and truthful statuses. Live verification uses isolated `ChatGPT QA` project and task fixtures in a normal ChatGPT chat, exercises every read/write path, confirms results in the installed ShipBar app, then moves fixtures to Trash and permanently deletes only after explicit approval.

