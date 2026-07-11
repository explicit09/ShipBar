# Waiting Row Badge Fix Design

## Goal

Keep Waiting rows compact and readable at every supported macOS window width while displaying a complete, human-readable run status.

## Verified Problems

- `ShipBarStateBadge` expands vertically inside `FocusTaskRowView`, producing tall icon-only pills and uneven Waiting rows.
- The project workspace formats `needsReview` as `Needsreview` because it has a local, incomplete string replacement.

## Design

### Intrinsic badge sizing

`ShipBarStateBadge` remains the shared visual component. Its label will be one line, fixed to its intrinsic horizontal and vertical size, and given sufficient layout priority that the task title yields space first. It will not receive a hard-coded width or height, preserving accessibility text sizing and all status lengths.

### Shared status presentation

The human-readable label and symbol currently used by `ShipBarStateBadge` become reusable `AgentRunStatus` presentation properties. Waiting rows, Runs, reviews, and project Recent Runs use the same label source. `needsReview` renders as `Needs review`; `handedOff` renders as `Handed off`.

## Scope

- Modify `ShipBarStateBadge` and the project Recent Runs label.
- Preserve task selection, completion, run state, colors, icons, accessibility descriptions, and all navigation.
- Do not redesign unrelated rows or change persistence.

## Verification

- Add failing source/behavior contracts for intrinsic badge sizing and shared labels.
- Verify every `AgentRunStatus` display label.
- Run the complete macOS test suite and signed build.
- Re-run the isolated V2 preview at approximately 420-point and 800-point widths.
- Confirm both Waiting rows remain compact and display `Running` / `Needs review` in full.
- Confirm Runs badges remain visually unchanged.

