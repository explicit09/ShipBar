# ShipBar Free Personal Relay Design

## Goal

Make ShipBar available from ChatGPT web and mobile while the Mac is offline, with no OpenAI Platform model calls and no paid hosting requirement for normal personal use.

## Current platform decision

The first ChatGPT surface is a private Custom GPT Action, not a public MCP endpoint. ChatGPT Actions support API-key authentication and run on mobile after the GPT is created on web. Supabase's current hosted MCP guide explicitly covers unauthenticated MCP only, so publishing ShipBar task data through that path would violate the privacy requirement. The existing local MCP bridge remains the Codex/local read surface.

## Architecture

```text
ChatGPT Custom GPT (web/mobile)
  -> HTTPS + X-ShipBar-Key
Supabase Edge Function /shipbar-relay
  -> owner-scoped Postgres rows
Mac/iPhone ShipBar relay client
  -> durable local capture/run lifecycle
```

Supabase is a delivery relay, not the canonical ShipBar database. It stores compact task mirrors, queued captures, device heartbeats, queued execution requests, and compact results. Local SwiftData/CloudKit remains authoritative for full tasks and runs.

## Hosted API

- `GET /health`: authenticated relay health.
- `GET /tasks?query=`: search compact mirrored tasks.
- `GET /today`: return today's mirrored flight plan.
- `POST /captures`: idempotently queue a structured task capture.
- `GET /devices`: list devices and derive online state from recent heartbeats.
- `POST /executions`: queue a Codex execution for a selected device.
- `GET /executions/{id}`: return truthful queued/claimed/running/review/completed/failed status.
- `POST /sync/pull`: device claims pending captures and executions.
- `POST /sync/push`: device upserts mirrors, heartbeats, acknowledgements, and results.

Every mutating request accepts a client-generated idempotency key. The Edge Function validates one high-entropy `X-ShipBar-Key` stored only as a Supabase secret and in the private GPT Action configuration/device Keychain. The database is not exposed directly to anonymous or authenticated Data API clients.

## Data and security

Tables: `relay_owners`, `task_mirrors`, `capture_queue`, `devices`, and `execution_queue`. Every table has RLS enabled. No `anon` or `authenticated` table grants are required because only the Edge Function's secret-scoped server client accesses them. The API key is hashed before storage and compared in constant time. Repository contents, task prompt snapshots, evidence files, and OpenAI credentials are never stored in Supabase.

## Sync truth

- `queued`: Supabase durably accepted the request.
- `claimed`: one device obtained the request with a lease.
- `delivered`: ShipBar saved it locally.
- `running`: the selected device actually began execution.
- `needs_review`, `completed`, `failed`, `canceled`: mirror ShipBar's real lifecycle.

Expired claims can be reclaimed. Idempotency keys prevent duplicate task creation after retries. A device is online only when its most recent heartbeat is less than 90 seconds old.

## Free-tier boundary

The relay is designed for the Supabase Free plan. It performs no model inference, stores no attachments, and uses short request/response functions. Free projects may pause after inactivity; the API must return a truthful unavailable error and clients retain local queued work for retry.

## Acceptance

1. Unauthenticated and incorrectly keyed requests reveal no data.
2. A ChatGPT Action can queue a capture while the Mac is offline and receive a durable queue ID.
3. When the Mac reconnects, it imports the capture exactly once and acknowledges delivery.
4. Search and Today return only compact mirrored task data.
5. Device status is truthful and execution requests require an explicit device ID.
6. Execution status never advances without a device report.
7. The OpenAPI schema imports into a Custom GPT Action and uses API-key authentication.
8. Local and hosted automated tests pass; a deployed smoke test proves the real endpoint before completion is claimed.
