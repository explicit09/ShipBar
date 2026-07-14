# ShipBar Free Personal Relay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a private Supabase relay that a Custom GPT can use from web/mobile and ShipBar devices can drain after reconnecting.

**Architecture:** A Supabase Edge Function authenticates a private `X-ShipBar-Key`, validates compact JSON requests, and accesses private relay tables with a server-only secret. A small local relay worker maps cloud captures and execution requests into the existing signed ShipBar bridge. The Action package contains the exact OpenAPI contract and GPT instructions.

**Tech Stack:** Supabase Postgres 17, RLS, Supabase Edge Functions (Deno 2), TypeScript, Swift 6, Swift Testing, OpenAPI 3.1.

## Global Constraints

- Supabase is a queue and compact mirror, not ShipBar's source of truth.
- No model API calls, attachments, repository contents, prompt snapshots, service-role keys, or OpenAI credentials in the relay.
- Every exposed table has RLS enabled; direct `anon` and `authenticated` table access is revoked.
- Every mutation is idempotent and every lifecycle status is reported truthfully.
- Hosted MCP remains disabled until an authenticated platform path is available; ChatGPT uses a private GPT Action.

---

### Task 1: Private relay schema

**Files:**
- Create: `supabase/config.toml`
- Create: `supabase/migrations/<generated>_create_shipbar_relay.sql`
- Create: `supabase/tests/relay_schema_test.sql`

**Interfaces:**
- Produces: `relay_owners`, `task_mirrors`, `capture_queue`, `devices`, `execution_queue` and claim indexes.

- [ ] Write pgTAP assertions first for table existence, RLS, revoked client privileges, owner foreign keys, unique idempotency keys, valid status checks, and queue indexes.
- [ ] Run `supabase start && supabase test db`; verify RED because the tables do not exist.
- [ ] Create the imperative migration with `supabase migration new create_shipbar_relay` and add the minimal schema/policies.
- [ ] Re-run `supabase test db`; verify all schema assertions pass.
- [ ] Run `supabase db advisors` (or the available advisor equivalent) and resolve relay findings.
- [ ] Commit `feat: add private relay schema`.

### Task 2: Authenticated Edge Function API

**Files:**
- Create: `supabase/functions/shipbar-relay/domain.ts`
- Create: `supabase/functions/shipbar-relay/domain_test.ts`
- Create: `supabase/functions/shipbar-relay/index.ts`
- Create: `supabase/functions/shipbar-relay/index_test.ts`

**Interfaces:**
- Consumes: relay tables from Task 1.
- Produces: `GET /health`, `/tasks`, `/today`, `/devices`, `/executions/:id`; `POST /captures`, `/executions`, `/sync/pull`, `/sync/push`.

- [ ] Write Deno tests first for missing/wrong keys, constant-time key checks, validation, idempotency, online-device derivation, claim lease expiry, and truthful status transitions.
- [ ] Run `deno test supabase/functions/shipbar-relay`; verify RED from missing domain/router implementations.
- [ ] Implement pure validation/auth/domain helpers, then the request router using injected persistence so behavior tests need no network.
- [ ] Run the focused Deno tests; verify GREEN.
- [ ] Serve against local Supabase and smoke-test unauthorized, queue, search, pull, acknowledge, device, and execution flows with `curl`.
- [ ] Commit `feat: add authenticated ShipBar relay API`.

### Task 3: ChatGPT Action package

**Files:**
- Create: `Integrations/shipbar-gpt-action/openapi.yaml`
- Create: `Integrations/shipbar-gpt-action/instructions.md`
- Create: `Integrations/shipbar-gpt-action/README.md`
- Create: `Integrations/shipbar-gpt-action/test/openapi_test.ts`

**Interfaces:**
- Consumes: hosted API from Task 2.
- Produces: importable OpenAPI 3.1 Action contract and private-GPT setup instructions.

- [ ] Write a schema test first asserting every operation ID, API-key header scheme, idempotency header, confirmation descriptions, and absence of internal sync endpoints from the GPT surface.
- [ ] Run the test and verify RED because the Action schema is absent.
- [ ] Implement the minimal OpenAPI schema exposing capture, search, Today, devices, execution queueing, and execution status.
- [ ] Add GPT instructions that confirm writes, distinguish queued from running, and never claim device delivery before status proves it.
- [ ] Re-run the Action tests and commit `feat: add private ShipBar GPT Action`.

### Task 4: ShipBar device relay worker

**Files:**
- Create: `Integrations/shipbar-relay-worker/src/client.ts`
- Create: `Integrations/shipbar-relay-worker/src/worker.ts`
- Create: `Integrations/shipbar-relay-worker/test/worker.test.ts`
- Modify: `Sources/Shared/Bridge/ShipBarBridgeProtocol.swift`
- Modify: `Sources/Mac/Bridge/ShipBarBridgeProcessor.swift`
- Modify: `Sources/CLI/ShipBarCLICore.swift`
- Test: `Tests/ShipBarTests/ShipBarCLIContractTests.swift`
- Test: `Tests/ShipBarTests/ShipBarBridgeProcessorTests.swift`

**Interfaces:**
- Consumes: `/sync/pull`, `/sync/push`, signed `shipbarctl` bridge.
- Produces: one-time capture delivery, device heartbeats, compact task mirror pushes, and truthful execution lifecycle updates.

- [ ] Write failing Swift tests for `queue-capture --id --title --description` and bridge idempotency.
- [ ] Implement the closed bridge command by routing through ShipBar's durable capture path; run focused Swift tests GREEN.
- [ ] Write failing worker tests for offline retention, retry, duplicate pull, CLI failure, acknowledgement-after-save, heartbeat, and execution device matching.
- [ ] Implement the worker and launch configuration with secrets loaded from Keychain/environment, never source files.
- [ ] Run TypeScript and full macOS tests, then a preview-data worker cycle.
- [ ] Commit `feat: sync ShipBar devices through personal relay`.

### Task 5: Deploy and prove the real free relay

**Files:**
- Create: `docs/reviews/2026-07-13-shipbar-free-relay-verification.html`

**Interfaces:**
- Consumes: Tasks 1-4.
- Produces: linked Supabase Free project, deployed function, configured private GPT Action, and runtime evidence.

- [ ] Create or select a dedicated Supabase project named `ShipBar Relay`; do not reuse an unrelated database.
- [ ] Apply the migration, set a generated relay key as a project secret, deploy the function, and run advisors.
- [ ] Verify the deployed endpoint rejects no-key/wrong-key requests and passes the complete authenticated smoke flow.
- [ ] Import `openapi.yaml` into a private Custom GPT on web using custom-header API-key auth.
- [ ] From ChatGPT mobile, queue a capture while the Mac worker is stopped; then start it and verify exactly-once delivery in ShipBar.
- [ ] Queue a Codex execution for an online device and verify status remains queued until that device claims it.
- [ ] Record exact pass/fail/blocker evidence in the HTML review and commit `docs: verify free personal relay`.

