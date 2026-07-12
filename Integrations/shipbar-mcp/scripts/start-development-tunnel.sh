#!/usr/bin/env bash
# Development-only: expose the ShipBar MCP server to ChatGPT through an
# AUTHENTICATED tunnel. Refuses to start without credentials so a public
# unauthenticated endpoint can never appear by accident.
set -euo pipefail

PORT="${SHIPBAR_MCP_PORT:-8807}"
USER_NAME="${SHIPBAR_TUNNEL_USER:-}"
PASSWORD="${SHIPBAR_TUNNEL_PASSWORD:-}"

if [[ -z "$USER_NAME" || -z "$PASSWORD" ]]; then
  echo "error: set SHIPBAR_TUNNEL_USER and SHIPBAR_TUNNEL_PASSWORD first." >&2
  echo "       This script never starts an unauthenticated public tunnel." >&2
  exit 1
fi
if [[ ${#PASSWORD} -lt 12 ]]; then
  echo "error: SHIPBAR_TUNNEL_PASSWORD must be at least 12 characters." >&2
  exit 1
fi
if ! command -v ngrok >/dev/null 2>&1; then
  echo "error: ngrok is required (brew install ngrok), and must be logged in." >&2
  exit 1
fi
if [[ ! -f "$(dirname "$0")/../dist/server.js" ]]; then
  echo "error: build first: npm run build" >&2
  exit 1
fi

cd "$(dirname "$0")/.."

echo "Starting stdio → Streamable HTTP bridge on 127.0.0.1:${PORT} ..."
npx --yes supergateway@3.4.0 \
  --stdio "node dist/server.js" \
  --outputTransport streamableHttp \
  --port "$PORT" \
  --host 127.0.0.1 &
BRIDGE_PID=$!
trap 'kill "$BRIDGE_PID" 2>/dev/null || true' EXIT

sleep 2

echo "Starting authenticated ngrok tunnel ..."
echo "Add the printed https URL in ChatGPT → Settings → Connectors (Developer Mode)"
echo "with basic auth ${USER_NAME}:<your password>."
exec ngrok http "$PORT" --basic-auth "${USER_NAME}:${PASSWORD}"
