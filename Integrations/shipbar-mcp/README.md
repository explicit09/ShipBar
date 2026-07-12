# ShipBar MCP Server

A local Model Context Protocol server that gives ChatGPT truthful,
read-only access to your ShipBar tasks and agent runs. It talks to the
running ShipBar menu app exclusively through the signed helper at
`/Applications/ShipBar.app/Contents/Helpers/shipbarctl` — it never reads
ShipBar's database or any other local files.

## Capabilities

**Read/search tools (always registered):**

| Tool | Returns |
| --- | --- |
| `search_tasks` | Task summaries matching a title/description query |
| `get_today` | Today's flight plan, in focus order |
| `get_task` | One task with its description |
| `list_prepared_runs` | Agent runs prepared for Codex |
| `get_run_status` | Truthful run state, no prompt body |

**Write tools: none on ChatGPT Personal Pro.** Write adapters exist in
code but register only when BOTH are true: the connected surface is in
the explicit write-enabled allowlist (no production surface is today)
and `SHIPBAR_ENABLE_MCP_WRITES=1` is set. Unknown surfaces fail closed.
A disabled write can never claim success — it is simply not registered.

**Privacy boundaries:** prompt bodies, API keys, and anything outside
ShipBar's own task/run summaries never leave the machine. Tool results
are whitelist-filtered before they reach the model.

## Setup

```bash
cd Integrations/shipbar-mcp
npm install
npm run build
npm test        # 13 tests
```

Run locally (stdio):

```bash
node dist/server.js
# SHIPBARCTL_PATH=<path> overrides the helper location for development
```

The ShipBar menu app must be running on this Mac; otherwise tools return
an actionable "open ShipBar and try again" error rather than stale data.

## Connecting ChatGPT (development)

ChatGPT custom connectors need an HTTPS endpoint. For development, bridge
stdio to Streamable HTTP and tunnel it **with authentication** — never
expose an unauthenticated public endpoint:

```bash
export SHIPBAR_TUNNEL_USER=you
export SHIPBAR_TUNNEL_PASSWORD='a-long-random-secret'
./scripts/start-development-tunnel.sh
```

Then in ChatGPT (web) → Settings → Connectors → Developer Mode → add the
printed HTTPS URL with the basic-auth credentials. Record the capability
list ChatGPT shows; on Personal Pro it must list only the five read
tools.

## Stop / revoke

- Stop the tunnel script (Ctrl-C) — the URL dies immediately.
- Remove the connector in ChatGPT settings to revoke the connection.
- Quit ShipBar to make every tool return the unavailable state.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| "ShipBar did not answer in time" | Menu app not running | Open ShipBar.app |
| "helper is unavailable: … exit code 4" | App Group/entitlement issue | Reinstall the signed ShipBar build |
| Tools missing in ChatGPT | Wrong surface or stale connector | Re-add the connector; check `SHIPBAR_SURFACE` |
