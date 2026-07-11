# Compact Status Menu Design

## Problem

ShipBar uses native `NSMenuItem` titles for Today tasks and Projects. A long dynamic title becomes the menu's intrinsic width, so one verbose task can stretch the entire status menu almost across the display.

## Approved behavior

- Keep the native macOS menu, keyboard navigation, submenus, icons, and shortcuts.
- Target an overall menu width of approximately 480 points.
- Limit the dynamic text portion of task and project rows to a measured width budget so static icons, metadata, shortcuts, and submenu arrows still fit.
- Truncate at a grapheme boundary and append a single ellipsis.
- Short titles remain unchanged.
- The complete task or project title remains available through the menu item's hover tooltip and through the existing open/detail action.
- Static footer and capture items remain unchanged.

## Architecture

Create a small macOS-only text-fitting utility that accepts a string, font, and maximum rendered width. It returns the original string when it fits and otherwise finds the longest grapheme-safe prefix that fits with an ellipsis.

`StatusItemMenuController` will use this utility when constructing task attributed titles and project menu titles. Task metadata is measured first; the remaining budget is assigned to the task title. Project count text remains visible while only the project name is truncated.

This preserves `NSMenu` behavior and solves the width at its source instead of replacing the menu with a custom SwiftUI panel.

## Width contract

- Dynamic attributed menu-label budget: 400 points.
- Expected total menu width after native icon, padding, key-equivalent, and submenu chrome: approximately 480 points.
- This is a cap, not a forced fixed width; menus with short content remain naturally narrower.

## Verification

- Unit-test short text, long text, emoji/grapheme safety, ellipsis width, and deterministic output.
- Add a contract ensuring both task and project rows use the fitting utility and preserve tooltips.
- Build, sign, reinstall `/Applications/ShipBar.app`, and open the real menu with the reported long podcast title.
- Measure the menu screenshot/window bounds and confirm it is close to 480 points rather than screen-wide.
- Confirm task selection, project submenus, keyboard shortcuts, and full-title hover behavior remain intact.

