# ShipBar Codex Plugin

Lets Codex claim prepared ShipBar work, run it on the machine the user
selected through Codex Remote, and return truthful status and evidence.

## How it works

ShipBar (the macOS menu app) prepares agent runs with a frozen prompt
and repository path. This plugin drives the run lifecycle through the
signed local helper embedded in the app:

```
/Applications/ShipBar.app/Contents/Helpers/shipbarctl
```

The helper exchanges versioned JSON envelopes with the running menu app
over the ShipBar App Group — a closed command set, local-only, with no
arbitrary shell execution:

| Command | Effect |
| --- | --- |
| `list-prepared` | Prepared Codex runs with title, project, repository |
| `get-context --run <id>` | Frozen prompt, task description, repository |
| `claim --run <id>` | Prepared → Handed off (validates the repository) |
| `mark-running --run <id>` | Handed off → Running |
| `request-review --run <id> --summary … --evidence …` | Running → Needs review; evidence must live inside the run repository |
| `mark-failed --run <id> --message …` | Truthful failure |
| `cancel --run <id> --message …` | Abandon the run |

Exit codes: `0` success, `1` usage, `2` command refused, `3` timeout
(ShipBar not running), `4` bridge unavailable.

## Skills

- **run-shipbar-task** — list, confirm, claim, execute, attach
  evidence, request review.
- **review-shipbar-run** — verify evidence and correct run state
  truthfully.

## Install

Copy or symlink `plugins/shipbar` into your Codex plugins directory,
then confirm the helper responds:

```
/Applications/ShipBar.app/Contents/Helpers/shipbarctl list-prepared
```

Requires the ShipBar menu app to be running on the same Mac.
