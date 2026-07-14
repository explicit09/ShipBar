# ShipBar Clean Data, Icons, and Selection Design

## Goal

ShipBar should open with only intentional personal data, use a calm graphite selection language, and present the same recognizable ShipBar mark on macOS, iPhone, and ChatGPT.

## Data cleanup

- Stop creating `LEARN-X`, `vedit`, and `Technologia` automatically in production stores.
- Remove those three seeded projects from the live store. Move any tasks they contain to Inbox before removing the projects so potentially useful tasks survive.
- Remove the empty `New Project` placeholder when it has no meaningful content.
- Permanently remove the known synthetic ChatGPT QA project and task records created by relay, bridge, and productivity verification.
- Keep `ShipBarV2PreviewData` only as an explicitly enabled, in-memory QA harness. Preview records must never read, write, or sync through the production store.
- Take a before snapshot, perform the targeted cleanup by stable identifiers where available, then take an after snapshot. Do not match broad user-authored words such as `test` or `ChatGPT`.

## Selection and focus language

- Replace the shared saturated-blue selection surface with a neutral graphite elevation.
- Selected cards and navigation items use an off-white foreground, a subtle neutral border, and restrained shadow/elevation.
- Keyboard focus remains clearly visible through a neutral high-contrast focus outline rather than the system-blue ring.
- Remove blue selected fills, borders, leading bars, and icon tints from the command strip, destination dock, task rows, flight plan, Inbox batch selection, and other shared selectable surfaces.
- Semantic state colors remain: orange for waiting, purple for handed-off/running, green for success, and red for destructive or failed states. These colors communicate state, not selection.
- Accessibility selected traits and keyboard navigation remain unchanged.

## Icon system

- Reuse the existing ShipBar paper-plane and signal mark as the single master identity.
- iPhone receives complete light, dark, and tinted 1024-point AppIcon variants with safe margins and no embedded corner radius.
- macOS receives a dedicated AppIcon asset catalog connected to the Mac target resource phase, with the mark composed for macOS icon geometry.
- ChatGPT receives a square hosted icon derived from the same master mark. The MCP server advertises the icon in server metadata where supported, and the installed ChatGPT plugin is refreshed so the generic letter avatar is replaced.
- The menu-bar status symbol may remain a monochrome system-style glyph; it must visually relate to the paper-plane mark and render crisply at menu-bar size.

## Verification

- Tests first for production seeding removal, targeted cleanup classification, neutral selection contracts, Mac resource wiring, iOS icon variants, and MCP icon metadata.
- Build and run the signed macOS app against the real store. Confirm the seeded projects and named QA records are gone while preserved tasks appear in Inbox.
- Build and inspect the iPhone app in Simulator or on the available signed device target, including Home Screen icon appearance.
- Refresh the production ChatGPT plugin and confirm the ShipBar icon appears in plugin management and a normal chat.
- Click through every selectable Mac and iPhone surface with Computer Use and confirm no saturated-blue selected or focus treatment remains.
- Run the complete Swift, relay/MCP, worker, and auth suites plus diff hygiene before completion.

## Safety boundary

The cleanup is limited to known seeded identifiers, the empty placeholder project, and known QA fixture identifiers/titles. User-authored tasks inside removed seeded projects are moved to Inbox. No broad text matching and no unrelated user data deletion are allowed.
