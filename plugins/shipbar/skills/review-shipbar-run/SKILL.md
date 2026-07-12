---
name: review-shipbar-run
description: Inspect a ShipBar run's frozen context and evidence, then report a truthful terminal status. Use when the user asks to review, verify, or close out a ShipBar run.
---

# Review a ShipBar Run

Use the signed helper at
`/Applications/ShipBar.app/Contents/Helpers/shipbarctl` for every
status read or change. The review decision itself (accept / request
changes) happens in the ShipBar app UI — this skill prepares that
decision with verified facts.

## Workflow

1. **Fetch the context.**
   ```
   shipbarctl get-context --run <runID>
   ```
   Read the frozen prompt, repository path, and current status.

2. **Verify the evidence, don't trust the summary.** Open the evidence
   files referenced by the run (they live inside the run repository).
   Re-run the checks they describe when practical — tests, builds, or
   the exact reproduction steps.

3. **Report findings truthfully.** Summarize what the evidence proves
   and what it does not. If evidence is missing or stale, say so
   plainly instead of inferring success.

4. **Correct wrong states through the helper only:**
   - Evidence shows the work is broken:
     `shipbarctl mark-failed --run <runID> --message "<verified failure>"`
   - Run is obsolete:
     `shipbarctl cancel --run <runID> --message "<reason>"`
   - Acceptance and "request changes" stay in the ShipBar app, where
     the user reviews with full context.

## Hard rules

- Never mark a run failed or canceled without evidence you inspected.
- Never edit ShipBar's database, CloudKit records, or App Group files
  directly.
- A `shipbarctl` refusal is the truth about run state — relay it, do
  not work around it.
