# ShipBar macOS Navigation Controls

## Goal

Make every nested macOS surface easy to leave without adding text-heavy controls.

## Design

- Use icon-only navigation buttons.
- Use `chevron.left` for returning to the previous ShipBar surface.
- Use `xmark` for dismissing a sheet, overlay, or standalone detail window.
- Give every control a minimum 44 × 44 point interaction target.
- Keep the icon visually quiet and consistent with ShipBar's graphite interface.
- Add a tooltip and an accessibility label such as “Back to Projects” or “Close” even though no label is drawn onscreen.
- Preserve Escape and existing keyboard shortcuts as secondary navigation.

## Affected Surfaces

1. Project workspace: replace the small text link with a large chevron button.
2. Task detail window: add an xmark button that closes the window.
3. Run review sheet: add an xmark button that dismisses the sheet.
4. Global capture sheet: add an xmark button that cancels capture.
5. Command palette: replace the small `esc` badge with an xmark button while retaining Escape.
6. macOS settings sheets: add an xmark button to sheets that currently rely on implicit dismissal.

## Implementation Boundary

Create one reusable macOS navigation-icon control and use it on the six affected surfaces. Do not restructure the app's window or navigation architecture, and do not change iOS behavior.

## Verification

- Add source-contract tests for the shared control, symbols, accessibility labels, and 44-point target.
- Run the complete Swift test suite.
- Build and install `/Applications/ShipBar.app`.
- Click through all six affected surfaces in the installed app and confirm both the visible control and its behavior.
- Confirm Escape and existing shortcuts still work.

