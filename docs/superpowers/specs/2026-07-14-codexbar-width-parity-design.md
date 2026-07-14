# ShipBar CodexBar Width Parity Design

**Date:** 2026-07-14
**Status:** Approved for planning after user review

## Goal

Make the ShipBar menu-bar menu feel as compact as the installed CodexBar 0.42.1 menu. CodexBar uses a 310-point base menu width. ShipBar currently allows dynamic labels to consume 360 points before AppKit adds menu chrome, which produces a menu around 470 points wide.

## Chosen Design

ShipBar will target a rendered menu width of approximately 310 points, with a small AppKit tolerance of up to 10 points. The implementation will:

- define the 310-point target explicitly;
- reduce the dynamic text budget to account for icons, menu padding, shortcuts, and submenu arrows;
- truncate long task and project names with one ellipsis;
- retain the complete task or project name in its tooltip;
- keep all current menu sections, actions, shortcuts, and submenus unchanged.

The implementation will continue using the native `NSMenu`. Replacing the menu with a custom popover is out of scope because it would add navigation, accessibility, keyboard, and positioning complexity without improving this width fix.

## Sizing Behavior

The menu width must not grow with unusually long task or project names. Dynamic labels will be fitted into the content budget before they are assigned to menu items. Fixed commands such as Quick Capture, Settings, and Quit remain unchanged because they already fit inside the target.

Success criteria:

- normal and long-title fixtures render between 310 and 320 points wide;
- long titles use a single trailing ellipsis;
- tooltips expose the full untruncated text;
- keyboard shortcuts and submenu arrows remain visible;
- no horizontal clipping affects icons, metadata, or commands.

## Verification

Implementation will follow test-first development:

1. Add a failing contract test for the 310-point target and reduced dynamic content budget.
2. Add or update fitting tests for long task and project labels.
3. Make the smallest sizing change that passes those tests.
4. Run the complete Swift test suite and macOS build.
5. Install the rebuilt app and manually compare the open ShipBar menu with CodexBar on the same display.

## Non-Goals

- redesigning menu content;
- changing row height, typography, colors, or task limits;
- rebuilding the menu as a custom popover;
- changing the main ShipBar window.
