# ShipBar Personal Pro ChatGPT Surface Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose truthful ShipBar read/search tools to ChatGPT Personal Pro now and keep write adapters safely disabled until the account surface supports them.

**Architecture:** Build a local TypeScript MCP server that calls the signed `shipbarctl` helper, publish it through OpenAI's supported secure tunnel for development, and advertise only capabilities allowed by the connected ChatGPT surface.

**Tech Stack:** TypeScript, Node.js, Model Context Protocol SDK, Zod, Vitest, secure MCP tunnel.

## Global Constraints

- Personal Pro exposes only supported read/search tools.
- Disabled writes are not registered and never claim success.
- Authentication scopes every result to the current ShipBar user.
- API keys, prompt bodies, arbitrary filesystem data, and unrelated local data are excluded.
- The server delegates to ShipBar lifecycle/query APIs; it does not read SwiftData files directly.

---

### Task 1: MCP package and read tools

**Files:**
- Create: `Integrations/shipbar-mcp/package.json`
- Create: `Integrations/shipbar-mcp/tsconfig.json`
- Create: `Integrations/shipbar-mcp/src/server.ts`
- Create: `Integrations/shipbar-mcp/src/shipbar-client.ts`
- Create: `Integrations/shipbar-mcp/src/tools/read-tools.ts`
- Create: `Integrations/shipbar-mcp/test/read-tools.test.ts`

- [ ] Initialize the package with locked dependencies for the current official MCP SDK, Zod, TypeScript, and Vitest.
- [ ] Add failing tests for `search_tasks`, `get_today`, `get_task`, `list_prepared_runs`, and `get_run_status`, including empty results, helper timeout, invalid JSON, and redaction.
- [ ] Verify RED with `npm test`.
- [ ] Implement a spawned `shipbarctl` client with argument arrays rather than shell interpolation, bounded timeout, output-size limit, and typed schemas.
- [ ] Register read-only tools with accurate annotations and compact structured results.
- [ ] Run tests, typecheck, and a local MCP inspector session; commit `feat: expose ShipBar read tools over MCP`.

### Task 2: Capability-gated write adapters

**Files:**
- Create: `Integrations/shipbar-mcp/src/capabilities.ts`
- Create: `Integrations/shipbar-mcp/src/tools/write-tools.ts`
- Test: `Integrations/shipbar-mcp/test/capabilities.test.ts`

- [ ] Add failing tests proving Personal Pro registers zero write tools, unknown surfaces fail closed, and an explicitly supported future surface registers `create_task`, `update_task`, `complete_task`, and `prepare_run` with confirmation/destructive annotations.
- [ ] Verify RED.
- [ ] Implement immutable capability discovery from authenticated session metadata plus `SHIPBAR_ENABLE_MCP_WRITES`; both must allow writes. Disabled calls return a capability error if reached indirectly.
- [ ] Route future adapters through the durable capture queue and run lifecycle; never directly mutate storage.
- [ ] Run tests and commit `feat: gate ShipBar MCP write capabilities`.

### Task 3: Personal Pro connection and secure tunnel

**Files:**
- Create: `Integrations/shipbar-mcp/README.md`
- Create: `Integrations/shipbar-mcp/scripts/start-development-tunnel.sh`
- Create: `docs/reviews/shipbar-chatgpt-mcp-verification.html`

- [ ] Configure the current official secure MCP tunnel without exposing a public unauthenticated endpoint.
- [ ] Connect it in ChatGPT Developer Mode on Personal Pro and record the exact capability list.
- [ ] Verify every read/search tool with real ShipBar preview data and confirm no write tool appears.
- [ ] Verify offline Mac behavior returns an actionable unavailable state rather than stale success.
- [ ] Document setup, pairing, privacy, stop/revoke, and troubleshooting steps; commit `docs: verify ShipBar ChatGPT connection`.

### Task 4: Complete end-to-end acceptance

- [ ] From ChatGPT mobile, create structured task text and Share it to ShipBar while Mac is offline.
- [ ] Sync the imported task to Mac and prepare its Codex run.
- [ ] Use ChatGPT mobile Codex Remote to select the paired Mac and invoke the ShipBar plugin.
- [ ] Complete a safe fixture task, attach diff/test evidence, and request review.
- [ ] Confirm ChatGPT read tools show the task/run state and both Apple apps show the same result.
- [ ] Confirm OpenAI Platform usage shows no new model API call from capture enrichment.
- [ ] Produce `docs/reviews/shipbar-chatgpt-codex-e2e.html` with timestamps, hashes, screenshots, limitations, and proof boundaries.

