---
name: run-shipbar-task
description: Claim a prepared ShipBar run, execute it on this machine, and report truthful status and evidence back through shipbarctl. Use when the user asks to run, pick up, or work on a ShipBar task.
---

# Run a ShipBar Task

ShipBar is the source of truth for run status. Every status change goes
through the signed helper — never claim a ShipBar status you did not
receive as a successful `shipbarctl` response.

The helper lives at:

```
/Applications/ShipBar.app/Contents/Helpers/shipbarctl
```

If that path is missing, stop and tell the user to install the current
ShipBar build. Do not simulate the helper or edit ShipBar data directly.

## Workflow

1. **List prepared work.**
   ```
   shipbarctl list-prepared
   ```
   Show the user the prepared runs (title, project, repository). If the
   list is empty, stop — never invent work.

2. **Show the frozen context.**
   ```
   shipbarctl get-context --run <runID>
   ```
   Present the frozen prompt and task description exactly as returned.

3. **Confirm before claiming.** Ask the user to confirm the exact run,
   this device, and the repository path from the context. Verify the
   repository exists locally (`test -d <repositoryPath>`) and is the
   repo they expect (`git -C <repositoryPath> remote -v`). Codex Remote
   owns device pairing and host selection — if this machine is not the
   intended host, stop.

4. **Claim the run.** Only after explicit confirmation:
   ```
   shipbarctl claim --run <runID>
   ```
   A refusal (non-zero exit or `errorMessage`) means someone else owns
   the run or its state changed — report that truthfully and stop.

5. **Mark it running when work actually starts:**
   ```
   shipbarctl mark-running --run <runID>
   ```

6. **Do the work with normal Codex practice** inside the confirmed
   repository: follow the frozen prompt, run the project's tests, and
   verify the change end to end. No ShipBar command executes shell
   work for you — the bridge only carries status.

7. **Attach evidence and request review.** Evidence files must live
   inside the run repository (for example `docs/reviews/…`):
   ```
   shipbarctl request-review --run <runID> \
     --summary "<one-paragraph truthful summary>" \
     --evidence <absolute path inside the repository>
   ```

## Recovery

- Work failed and cannot proceed:
  `shipbarctl mark-failed --run <runID> --message "<what actually broke>"`
- User abandons the run:
  `shipbarctl cancel --run <runID> --message "<why>"`
- Timeout (`exit 3`) means the ShipBar menu app is not running — ask
  the user to open ShipBar, then retry the same command; requests are
  idempotent by UUID.

## Hard rules

- Never bypass `shipbarctl` to mutate ShipBar state.
- Never report Prepared → Handed off → Running → Needs review
  transitions that the helper did not acknowledge.
- Never pass secrets or API keys through summaries or evidence paths.
