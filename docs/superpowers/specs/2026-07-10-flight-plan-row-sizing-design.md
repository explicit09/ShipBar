# Flight Plan Row Sizing Design

## Problem

Long task titles currently increase the Flight Plan row's ideal width and can add a second line, making the top card expand instead of remaining calm and stable.

## Approved behavior

- Flight Plan rows keep a consistent compact height.
- The title column is constrained to the width available between the position control and trailing remove control.
- Titles render on one line and truncate at the tail with an ellipsis.
- Reorder and remove controls keep their fixed positions and hit targets.
- The complete title remains available through the existing task-detail action and a hover tooltip.
- The row and Flight Plan card never request more width than their parent container.
- Now, Next, Waiting, and Completed rows keep their existing two-line behavior; this correction is scoped to Flight Plan rows.

## Implementation seam

`FocusTaskRowView` will derive compact title behavior from `.flightPlan` mode. The text column will accept compression with a zero minimum width, while the row receives an explicit compact height only in Flight Plan mode.

## Verification

- Add a focused source/layout contract that fails before the sizing constraints exist.
- Build and inspect the signed app at 420 × 620 and at a wide window size with an intentionally long preview task title.
- Confirm the row and card widths remain fixed, the title truncates, controls remain visible, and the full title is exposed by accessibility/help text.
- Run the full macOS test suite, signed build, strict code-sign verification, and diff hygiene check.

