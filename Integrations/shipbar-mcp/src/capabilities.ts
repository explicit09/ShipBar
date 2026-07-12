/**
 * Capability discovery for the connected ChatGPT surface.
 *
 * ChatGPT Personal Pro supports custom-connector read/search tools only,
 * so writes stay disabled there. Unknown surfaces fail closed. A future
 * surface must be listed here explicitly AND the operator must set
 * SHIPBAR_ENABLE_MCP_WRITES=1 before any write adapter is registered.
 */

export const READ_ONLY_SURFACES = new Set(["personal-pro"]);

/**
 * No current official OpenAI surface supports custom-MCP writes for this
 * account type. This set is intentionally empty of production surfaces;
 * the preview name exists so gating logic stays testable end to end.
 */
export const WRITE_ENABLED_SURFACES = new Set(["developer-write-preview"]);

export interface ShipbarCapabilities {
  readonly surface: string;
  readonly readsEnabled: boolean;
  readonly writesEnabled: boolean;
}

export function resolveCapabilities(
  surface: string,
  env: Record<string, string | undefined>,
): Readonly<ShipbarCapabilities> {
  const known = READ_ONLY_SURFACES.has(surface) || WRITE_ENABLED_SURFACES.has(surface);
  const writesEnabled =
    WRITE_ENABLED_SURFACES.has(surface) && env.SHIPBAR_ENABLE_MCP_WRITES === "1";
  return Object.freeze({
    surface,
    readsEnabled: known || surface === "personal-pro",
    writesEnabled,
  });
}
