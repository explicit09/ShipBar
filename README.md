# ShipBar

ShipBar is a native Apple utility for keeping a small personal queue of project tasks and AI-agent-ready prompts.

## V1

- macOS menu bar app using an AppKit status item with SwiftUI content.
- iPhone SwiftUI app target using the same shared model and views.
- SwiftData persistence with runtime CloudKit entitlement checks.
- Projects, tasks, status, priority, type, optional prompt, and copy prompt.
- Quick capture with simple prefix parsing, such as `vedit high feature: Add undo stack`.

## Development

Generate the Xcode project:

```sh
xcodegen generate
```

Run tests:

```sh
xcodebuild test -project ShipBar.xcodeproj -scheme ShipBarTests -destination 'platform=macOS'
```

Build macOS:

```sh
xcodebuild build -project ShipBar.xcodeproj -scheme ShipBarMac -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Unsigned local builds and iOS simulator builds use local SwiftData storage. Signed builds that include the `iCloud.com.tadies.ShipBar` container and CloudKit service entitlements use CloudKit; the in-app Settings screen reports which path is active.
