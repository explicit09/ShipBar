# ShipBar

ShipBar is a native Apple shipping cockpit for turning captured work into a focused daily plan, durable agent handoffs, and reviewable outcomes.

## V2

- macOS menu bar app using an AppKit status item with SwiftUI content.
- Today command center with a persistent Top 3 Flight Plan, Now, Next, Waiting, and completed work.
- Durable agent runs with prepared, handed off, running, needs-review, completed, failed, and canceled states.
- Review decisions keep the prompt snapshot, result summary, evidence URL, and task outcome together.
- Command–K search across destinations, projects, tasks, and runs.
- Batch Inbox triage for project assignment, Today, Someday, and confirmed deletion.
- Project outcomes, health metrics, scoped capture, progress, and recent run context.
- iPhone companion with Top 3, Waiting, Inbox swipe triage, run review, and truthful Ready-on-Mac handoffs.
- SwiftData persistence with runtime CloudKit entitlement checks.
- Direct CloudKit reconciliation for projects, tasks, focus state, runs, and deletion tombstones.
- Quick capture supports lists and prefixes such as `vedit high feature: Add undo stack`.

## Development

The signed Mac app keeps five destinations in a bottom dock: **Today**, **Inbox**, **Runs**, **Projects**, and **Settings**. Use Command–1 through Command–5 to switch between them. The command strip above the current destination opens cross-app search with Command–K and exposes global capture with the plus button.

Generate the Xcode project:

```sh
xcodegen generate
```

Run tests:

```sh
xcodebuild test -project ShipBar.xcodeproj -scheme ShipBarTests \
  -destination 'platform=macOS,arch=arm64' -quiet
```

Build macOS:

```sh
xcodebuild build -project ShipBar.xcodeproj -scheme ShipBarMac \
  -destination 'platform=macOS,arch=arm64' -quiet
```

Build the iOS simulator target:

```sh
xcodebuild build -project ShipBar.xcodeproj -scheme ShipBariOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO -quiet
```

If Xcode reports that the installed iOS platform is unavailable (currently `iOS 26.4 is not installed` on the review machine), record the simulator build as blocked rather than passing. Install the matching platform from Xcode > Settings > Components before rerunning.

Run the signed Mac app with isolated V2 review fixtures:

```sh
launchctl setenv SHIPBAR_V2_PREVIEW_DATA 1
open -na "$HOME/Library/Developer/Xcode/DerivedData/ShipBar-aidgviwwzrjwxnbmohonoazehacd/Build/Products/Debug/ShipBarMac.app" --args --open-main
launchctl unsetenv SHIPBAR_V2_PREVIEW_DATA
```

Preview mode always uses an in-memory store. It never reads, writes, or syncs the user's normal SwiftData/CloudKit store.

For the complete macOS verification rerun:

```sh
pkill -x ShipBarMac || true
xcodegen generate
xcodebuild test -project ShipBar.xcodeproj -scheme ShipBarTests \
  -destination 'platform=macOS,arch=arm64' -quiet
xcodebuild build -project ShipBar.xcodeproj -scheme ShipBarMac \
  -destination 'platform=macOS,arch=arm64' -quiet
git diff --check
```

## Truth boundary

ShipBar records what it can prove. Preparing a run is distinct from launching an agent; a run becomes handed off only after the Mac launch path is invoked. iPhone creates a `.prepared` run labeled “Ready on Mac” and does not claim that a desktop agent started. Result summaries and evidence are user-reviewable records, not automatic proof that external work succeeded.

Unsigned local builds and iOS simulator builds use local SwiftData storage. Signed builds that include the `iCloud.com.tadies.ShipBar` container and CloudKit service entitlements use CloudKit; the in-app Settings screen reports which path is active.
