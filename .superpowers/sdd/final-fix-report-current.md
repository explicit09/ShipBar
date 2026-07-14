# ShipBar final whole-branch fix report

Status: **DONE_WITH_CONCERNS**
Reviewed base/head: `b02460e` / `ad36445`
Fixed head before this report: `feb0a9f`

## Finding resolutions

1. **CloudKit manifest last-writer-wins — fixed.** Data records save first; the manifest now refetches the server record, unions remote and local IDs, saves with `.ifServerRecordUnchanged`, and retries change-tag conflicts up to six times. Tombstoned local task/project IDs are removed after union. The concurrent-device test races two compare-and-swap writers and proves both new IDs survive.
2. **Shared capture append/acknowledge race — fixed.** Every file read-modify-write operation now holds an OS `flock` on a sibling lock file, covering independent store instances/processes. A 25-way append/acknowledge race preserves the arriving capture.
3. **Idempotency payload rewrites — fixed.** Capture and execution enqueue use insert-once transactional RPCs. Existing canonical payloads return the existing row; mismatched reuse raises SQLSTATE `22000`, mapped to sanitized HTTP 409. Both mismatch cases have repository and pgTAP coverage.
4. **Non-atomic claims/transitions — fixed.** Claiming is one `FOR UPDATE SKIP LOCKED` RPC that rechecks queue status, lease expiry, owner, and target device in the update. Execution transitions use an expected-status/device compare-and-swap and raise when exactly one row is not updated. Capture acknowledgement also uses claim/device CAS. Focused tests cover live-lease theft, stale status, and wrong-device updates.
5. **Duplicate prepared runs on relay retry — fixed.** Relay execution ID flows through worker → `shipbarctl --preparation-key` → bridge request → durable unique preparation key on `AgentRun`; repeated preparation returns the existing run. Worker cycles coalesce while one is active. The retry test reproduces failed cloud push after local preparation, then verifies the same execution identity/local run is used.
6. **iOS target compile failure — fixed.** Shared bridge storage no longer references `homeDirectoryForCurrentUser`; non-macOS uses the user Application Support URL. A second iOS compile defect exposed by the fresh build (macOS-only capture xmark in an iOS-compiled property) is platform-guarded. Fresh generic iOS Simulator build passes.
7. **Incomplete capture lifecycle envelope — fixed.** Schema v2 persists `queued/imported/syncing/synced/failed`, attempt count, last attempt, and user-readable error. Legacy envelopes decode as schema v1 with safe defaults. Explicit begin/fail/retry/sync transitions and per-item inspection are available; the iOS importer records attempts and durable failure details.

## Minor findings

- Router now distinguishes validation (400), idempotency conflict (409), and sanitized storage unavailability (503).
- Plugin timeout recovery now reads `run-status` before any retry and no longer overstates cross-invocation UUID idempotency.
- The navigation verification HTML records the fresh iOS build separately from the approved macOS navigation click-through.

## TDD RED/GREEN evidence

- Capture lifecycle/race RED: focused `xcodebuild test ... SharedCaptureStoreTests` failed on missing `state`, diagnostics fields, transitions, and `envelope`. GREEN: focused Swift set passed, followed by the full suite.
- Preparation identity RED: bridge test required `preparationKey`; worker overlap test failed `expected ... 1 times, but got 2 times`. GREEN: bridge idempotency test passed; worker `8 passed`.
- Cloud manifest RED: focused test failed because `ManifestIDs` and `mergeManifest` did not exist. GREEN: concurrent CAS fixture test passed and the full suite remained green.
- iOS RED: initial fresh simulator build failed at `ShipBarRootView.swift:130: cannot find 'ShipBarNavigationIconButton' in scope`. GREEN: platform guard added; identical simulator build passed.
- Relay RED: repository tests failed to compile without `RelayConflictError`/`RelayStorageError`; router tests returned 400 instead of expected 409/503. GREEN: Deno relay suite `18 passed, 0 failed`.
- SQL behavior tests were authored for the RPC migration, but local RED/GREEN execution could not complete because Docker became unavailable during the first Supabase 17.6 image pull (see truth boundary).

## Verification matrix

- `xcodebuild test -project ShipBar.xcodeproj -scheme ShipBarTests -destination 'platform=macOS,arch=arm64' -quiet` — **PASS, 156/156**, 0 failed/skipped.
- `xcodebuild build ... -scheme ShipBarMac -destination 'platform=macOS,arch=arm64' -quiet` — **PASS**.
- `xcodebuild build ... -scheme ShipBariOS -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO -quiet` — **PASS**.
- `deno test --allow-env` for relay domain/router/repository — **PASS, 18/18**.
- GPT Action OpenAPI tests — **PASS, 4/4**.
- Relay worker `npm test` — **PASS, 8/8**; `npm run typecheck` — **PASS**.
- `supabase db lint --linked` — **PASS**, no schema errors.
- `supabase db push --linked --dry-run` — **PASS**, recognizes only `20260714052000_atomic_relay_operations.sql`; no remote mutation performed.
- `git diff --check` — **PASS** before report creation.
- Pre-existing Xcode duplicate-group and empty-supported-platform warnings remain; they did not fail tests/builds.

## Remaining truth boundary and exact external-only step

Local `supabase test db` / local lint are **not verified**. During the first Supabase 17.6 image pull, the Data volume fell to 383 MiB and Docker Desktop began returning `Docker Desktop is unable to start`. Removing only this run's temporary DerivedData recovered approximately 0.9 GiB, but Docker still would not start. Remote linked lint and dry-run succeeded, but they do not execute the new pgTAP behavior tests.

After Docker has working disk headroom, run exactly:

```sh
cd /Users/tadies/Projects/ShipBar/.worktrees/chatgpt-codex-bridge
supabase start
supabase db reset
supabase test db
supabase db lint --local
```

No credentials, deployment, merge, or push are otherwise required. The approved icon-only macOS navigation behavior and existing evidence remain intact.

## Commits

- `f5acc8e` — `fix: make bridge delivery durable across retries`
- `a2fcfb5` — `fix: make relay queue operations atomic`
- `feb0a9f` — `docs: clarify iOS readiness and retry recovery`

---

## Round 2 final-review recovery — 2026-07-14

Status: **DONE_WITH_CONCERNS**
Reviewed base: `feb0a9f`
Fixed implementation head: `8f8c24f`

### Finding resolutions

1. **Bridge save failures — fixed.** Every mutating command now uses an injected persistence operation, treats `false` as failure, rolls the `ModelContext` back, and returns a failed response. Tests cover preparation, queue capture, claim, running, review, failure, and cancellation paths and verify unsaved values cannot leak into a later save.
2. **Capture lifecycle and retention — fixed.** Captures enter durable `importing` before local save, move directly to `syncing` without an `imported` crash window, retain IDs through coalesced direct-sync passes, become `synced` only after CloudKit success, and persist actionable failure details after CloudKit failure. Synced diagnostics have a documented seven-day retention window, enforced after every successful reconciliation.
3. **Relay CAS conflict mapping — fixed.** SQLSTATE `P0001` from execution-transition and capture-acknowledgement compare-and-swap failures maps to `RelayStateConflictError`, then to a sanitized HTTP `409 state_conflict`; database details are not exposed.

### Exact RED / GREEN evidence

- **Swift RED (isolated base reconstruction):** applied only the new Swift tests to detached `feb0a9f`, then ran the focused processor/capture/coordinator command with isolated DerivedData. It exited **65** at compile time, including `cannot find type 'ShipBarSyncOutcome' in scope`, `extra trailing closure passed in call`, and missing capture-ID request APIs. This is the expected RED for the absent Round 2 behavior; the reviewed base also discarded the Boolean result of bridge saves.
- **Swift GREEN:** the identical focused suites passed on the fixed branch. The counted full run then passed **161/161**, with **0 failed and 0 skipped**.
- **Relay RED (isolated base reconstruction):** applied only the new relay tests to detached `feb0a9f`; `deno test --allow-env ...router_test.ts ...repository_test.ts` exited **1** with two type errors because `RelayStateConflictError` was not exported.
- **Relay GREEN:** `deno test --allow-env` for relay domain/router/repository passed **20/20**, including stale execution transition, wrong-device capture acknowledgement, and sanitized router response tests.

### Round 2 verification

- Focused bridge/capture/sync Swift suites — **PASS**.
- Full Swift suite — **PASS, 161/161**, 0 failed/skipped.
- macOS `ShipBarMac` arm64 build — **PASS**.
- generic iOS Simulator `ShipBariOS` build with signing disabled — **PASS**.
- relay Deno domain/router/repository suite — **PASS, 20/20**.
- `git diff --check` — **PASS** before this report update.
- Worker and GPT Action were not rerun because neither surface was touched in Round 2.

### Round 2 commits

- `a3cee60` — `fix: roll back failed bridge commands`
- `a0e447b` — `fix: tie captures to cloud sync outcomes`
- `8f8c24f` — `fix: map relay state conflicts to 409`

### Concerns / truth boundary

- Local pgTAP remains intentionally unverified because Docker/disk health was already documented as blocked; Round 2 did not change SQL.
- Existing Xcode duplicate-group and empty-supported-platform warnings remain non-fatal and unchanged.
