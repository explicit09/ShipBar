import { execFile } from "node:child_process";
import { z } from "zod";

export const DEFAULT_HELPER_PATH =
  "/Applications/ShipBar.app/Contents/Helpers/shipbarctl";

/** The ShipBar side of the bridge is unreachable or unusable. */
export class ShipbarUnavailableError extends Error {}

/** ShipBar answered, but refused the command. */
export class ShipbarCommandError extends Error {}

export interface ShipbarRunner {
  run(
    args: string[],
    timeoutMs: number,
  ): Promise<{ stdout: string; stderr: string; exitCode: number }>;
}

const envelopeSchema = z.object({
  requestID: z.string(),
  schemaVersion: z.literal(1),
  createdAt: z.string(),
  result: z.unknown().optional(),
  errorMessage: z.string().optional(),
});

export type ShipbarEnvelope = z.infer<typeof envelopeSchema>;

function defaultRunner(binaryPath: string): ShipbarRunner {
  return {
    run(args, timeoutMs) {
      return new Promise((resolve) => {
        // Argument array + no shell: nothing here is shell-interpolated.
        execFile(
          binaryPath,
          args,
          { timeout: timeoutMs, maxBuffer: 8_000_000 },
          (error, stdout, stderr) => {
            const exitCode =
              error && typeof (error as NodeJS.ErrnoException & { code?: unknown }).code === "number"
                ? ((error as unknown as { code: number }).code as number)
                : error
                  ? 4
                  : 0;
            resolve({ stdout: stdout ?? "", stderr: stderr ?? "", exitCode });
          },
        );
      });
    },
  };
}

export class ShipbarClient {
  private readonly runner: ShipbarRunner;
  private readonly timeoutMs: number;
  private readonly maxOutputBytes: number;

  constructor(options: {
    binaryPath?: string;
    runner?: ShipbarRunner;
    timeoutMs?: number;
    maxOutputBytes?: number;
  } = {}) {
    this.runner = options.runner ?? defaultRunner(options.binaryPath ?? DEFAULT_HELPER_PATH);
    this.timeoutMs = options.timeoutMs ?? 20_000;
    this.maxOutputBytes = options.maxOutputBytes ?? 4_000_000;
  }

  async call(args: string[]): Promise<ShipbarEnvelope> {
    const { stdout, stderr, exitCode } = await this.runner.run(args, this.timeoutMs);

    if (exitCode === 3) {
      throw new ShipbarUnavailableError(
        "ShipBar did not answer in time. Open the ShipBar menu app on your Mac and try again.",
      );
    }
    if (exitCode === 1 || exitCode === 4) {
      throw new ShipbarUnavailableError(
        `The ShipBar helper is unavailable: ${stderr.trim() || `exit code ${exitCode}`}`,
      );
    }
    if (stdout.length > this.maxOutputBytes) {
      throw new ShipbarUnavailableError(
        "The ShipBar helper returned more data than expected; refusing to parse it.",
      );
    }

    let parsed: unknown;
    try {
      parsed = JSON.parse(stdout);
    } catch {
      throw new ShipbarUnavailableError(
        "The ShipBar helper returned invalid JSON; no data is available.",
      );
    }

    const envelope = envelopeSchema.safeParse(parsed);
    if (!envelope.success) {
      throw new ShipbarUnavailableError(
        "The ShipBar helper returned an unrecognized envelope; no data is available.",
      );
    }
    if (envelope.data.errorMessage) {
      throw new ShipbarCommandError(envelope.data.errorMessage);
    }
    return envelope.data;
  }
}
