import { execFileSync } from "node:child_process";
import { hostname } from "node:os";
import { RelayClient, ShipBarClient } from "./client.js";
import { RelayWorker } from "./worker.js";

function required(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`${name} is required.`);
  return value;
}

function relayKey(): string {
  const environment = process.env.SHIPBAR_RELAY_KEY?.trim();
  if (environment) return environment;
  try {
    return execFileSync("/usr/bin/security", [
      "find-generic-password", "-s", "com.shipbar.relay", "-a", "default", "-w",
    ], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim();
  } catch {
    throw new Error(
      "SHIPBAR_RELAY_KEY is missing. Set it in the environment or save it in Keychain service com.shipbar.relay.",
    );
  }
}

const deviceId = process.env.SHIPBAR_DEVICE_ID?.trim() || hostname();
const worker = new RelayWorker({
  relay: new RelayClient(required("SHIPBAR_RELAY_URL"), relayKey()),
  shipbar: new ShipBarClient(process.env.SHIPBARCTL_PATH?.trim() || undefined),
  device: {
    id: deviceId,
    name: process.env.SHIPBAR_DEVICE_NAME?.trim() || hostname(),
    platform: "macos",
  },
});

async function run(): Promise<void> {
  const result = await worker.cycle();
  console.log(JSON.stringify({ ok: true, deviceId, ...result }));
}

if (process.argv.includes("--once")) {
  await run();
} else {
  await run();
  const timer = setInterval(() => void run().catch((error) => {
    console.error(error instanceof Error ? error.message : String(error));
  }), 30_000);
  process.on("SIGTERM", () => { clearInterval(timer); process.exit(0); });
  process.on("SIGINT", () => { clearInterval(timer); process.exit(0); });
}
