# ShipBar iOS Internal TestFlight Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a complete ShipBar 1.0 iPhone build to an internal TestFlight group containing only the owner.

**Architecture:** Keep `project.yml` as the generated Xcode project's source of truth, add release resources under `Resources/iOS`, and enforce the distributable bundle with source-contract tests before regenerating the project. Verify the same artifact progressively in simulator, on the paired iPhone, in a distribution archive, and finally in App Store Connect/TestFlight.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing, XcodeGen, Xcode 26.4, CloudKit, App Intents, Share Extension, App Store Connect/TestFlight.

## Global Constraints

- Display name is `ShipBar`; bundle ID is `com.tadies.ShipBar`.
- Marketing version is `1.0`; every upload uses a monotonically increasing integer build number.
- Device family is iPhone; minimum OS is iOS 17.
- Distribution is internal TestFlight only and the only tester is the owner.
- The phone prepares Codex runs for a Mac and never claims desktop execution before a Mac claims the run.
- TestFlight uses the production CloudKit environment; completion requires an observed phone-to-Mac and Mac-to-phone round trip.
- Preserve the user's unrelated untracked review artifacts.

---

### Task 1: Release configuration contract

**Files:**
- Create: `Tests/ShipBarTests/iOSReleaseContractTests.swift`
- Modify: `project.yml`
- Modify: `Config/iOS/Info.plist`
- Modify: `Config/ShareExtension/Info.plist`

**Interfaces:**
- Consumes: repository-root source files and the existing `ShipBarTests` source-contract pattern.
- Produces: one version source, iPhone-only device family, supported orientations, export-compliance metadata, and resource declarations used by the generated project.

- [ ] **Step 1: Write the failing release contract**

```swift
import Foundation
import Testing

@Suite("iOS release bundle contracts")
struct iOSReleaseContractTests {
    @Test("release identity and iPhone metadata are generated from project settings")
    func releaseIdentity() throws {
        let project = try source("project.yml")
        let info = try source("Config/iOS/Info.plist")
        #expect(project.contains("MARKETING_VERSION: \"1.0\""))
        #expect(project.contains("TARGETED_DEVICE_FAMILY: \"1\""))
        #expect(project.contains("Resources/iOS"))
        #expect(info.contains("$(MARKETING_VERSION)"))
        #expect(info.contains("$(CURRENT_PROJECT_VERSION)"))
        #expect(info.contains("ITSAppUsesNonExemptEncryption"))
        #expect(info.contains("UISupportedInterfaceOrientations"))
    }

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
```

- [ ] **Step 2: Run the focused test and observe failure**

Run: `xcodebuild test -project ShipBar.xcodeproj -scheme ShipBarTests -destination 'platform=macOS' -only-testing:ShipBarTests/iOSReleaseContractTests`

Expected: FAIL because the test is not yet part of the generated project or the release settings are absent.

- [ ] **Step 3: Make release settings authoritative**

Set `MARKETING_VERSION: "1.0"`, keep a unique integer `CURRENT_PROJECT_VERSION`, add `TARGETED_DEVICE_FAMILY: "1"`, `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`, and an iOS resources path in `project.yml`. Replace literal bundle versions in both iOS plists with `$(MARKETING_VERSION)` and `$(CURRENT_PROJECT_VERSION)`. Add `ITSAppUsesNonExemptEncryption = false` and the three iPhone orientations.

- [ ] **Step 4: Regenerate and pass the focused test**

Run: `xcodegen generate && xcodebuild test -project ShipBar.xcodeproj -scheme ShipBarTests -destination 'platform=macOS' -only-testing:ShipBarTests/iOSReleaseContractTests`

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit the release contract**

Run: `git add project.yml ShipBar.xcodeproj Config/iOS/Info.plist Config/ShareExtension/Info.plist Tests/ShipBarTests/iOSReleaseContractTests.swift && git commit -m "build: prepare iOS release metadata"`

### Task 2: Production privacy manifest and app icon

**Files:**
- Create: `Resources/iOS/PrivacyInfo.xcprivacy`
- Create: `Resources/iOS/Assets.xcassets/Contents.json`
- Create: `Resources/iOS/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Create: `Resources/iOS/Assets.xcassets/AppIcon.appiconset/ShipBar-AppIcon-1024.png`
- Modify: `Tests/ShipBarTests/iOSReleaseContractTests.swift`

**Interfaces:**
- Consumes: `Resources/iOS` resource path and `ASSETCATALOG_COMPILER_APPICON_NAME` from Task 1.
- Produces: `Assets.car`, a 1024 by 1024 App Store icon, and `PrivacyInfo.xcprivacy` embedded in the archived application.

- [ ] **Step 1: Extend the contract to require truthful resources**

Add tests that decode the asset JSON, assert the universal iOS 1024 image filename, inspect the PNG dimensions with ImageIO, and parse the privacy plist to assert `NSPrivacyTracking == false`, an empty tracking-domain array, a collected-data array, and an accessed-API array.

- [ ] **Step 2: Run the contract and observe missing resources**

Run the focused command from Task 1.

Expected: FAIL with missing `Resources/iOS/PrivacyInfo.xcprivacy` and asset-catalog files.

- [ ] **Step 3: Add the graphite-and-signal icon and manifest**

Generate original artwork with a graphite field, a clear white route/ship mark, and one blue-violet signal accent; crop it square and export exactly 1024 by 1024 pixels. Add the standard asset-catalog JSON. Add a valid privacy manifest declaring no tracking and only the data/API categories proven by source inspection; do not invent reasons or claim task/voice content remains on-device.

- [ ] **Step 4: Pass the resource contract and compile the catalog**

Run: `xcodegen generate && xcodebuild test -project ShipBar.xcodeproj -scheme ShipBarTests -destination 'platform=macOS' -only-testing:ShipBarTests/iOSReleaseContractTests && xcodebuild build -project ShipBar.xcodeproj -scheme ShipBariOS -destination 'generic/platform=iOS Simulator' -derivedDataPath "${TMPDIR%/}/ShipBar-iOS-release-check"`

Expected: test and simulator build succeed with no missing-AppIcon warning.

- [ ] **Step 5: Commit production resources**

Run: `git add Resources/iOS Tests/ShipBarTests/iOSReleaseContractTests.swift ShipBar.xcodeproj && git commit -m "feat: add ShipBar iOS release assets"`

### Task 3: Full build and archive verification

**Files:**
- Modify only files required by failures uncovered by the verification commands.
- Create: `docs/reviews/2026-07-14-ios-testflight-verification.html`

**Interfaces:**
- Consumes: generated Release configuration and production resources from Tasks 1 and 2.
- Produces: a passing source suite, signed device build, validated `.xcarchive`, and a brief HTML evidence report.

- [ ] **Step 1: Run the full Mac test suite**

Run: `xcodebuild test -project ShipBar.xcodeproj -scheme ShipBarTests -destination 'platform=macOS' -derivedDataPath "${TMPDIR%/}/ShipBarTests"`

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 2: Build the paired-device configuration**

Run: `xcodebuild build -project ShipBar.xcodeproj -scheme ShipBariOS -configuration Release -destination 'generic/platform=iOS' -derivedDataPath "${TMPDIR%/}/ShipBarDevice" -allowProvisioningUpdates`

Expected: `** BUILD SUCCEEDED **` with automatic signing and no orientation or icon errors.

- [ ] **Step 3: Archive the release**

Run: `xcodebuild archive -project ShipBar.xcodeproj -scheme ShipBariOS -configuration Release -destination 'generic/platform=iOS' -archivePath "${TMPDIR%/}/ShipBar.xcarchive" -allowProvisioningUpdates`

Expected: `** ARCHIVE SUCCEEDED **`.

- [ ] **Step 4: Inspect archive contents and entitlements**

Verify that `ShipBariOS.app` contains `Assets.car`, `PrivacyInfo.xcprivacy`, `Metadata.appintents`, and `PlugIns/ShipBarShareExtension.appex`. Inspect `Info.plist`, `embedded.mobileprovision`, and signed entitlements; report development versus distribution truthfully.

- [ ] **Step 5: Record concise evidence and commit any corrections**

Create one-screen HTML with pass/fail rows for tests, simulator, device build, archive contents, signing, CloudKit, upload, processing, and installation. Commit only relevant corrections and the report.

### Task 4: Paired-iPhone and production CloudKit proof

**Files:**
- Modify: `docs/reviews/2026-07-14-ios-testflight-verification.html`

**Interfaces:**
- Consumes: signed ShipBariOS build, paired device `2493FA8A-1842-5159-AE18-AE184A781ACC`, CloudKit container `iCloud.com.tadies.ShipBar`.
- Produces: hands-on navigation/capture proof and observed bidirectional production-data synchronization.

- [ ] **Step 1: Install and launch on the paired iPhone**

Use `xcrun devicectl device install app` with the built `.app`, then launch `com.tadies.ShipBar`; capture exact install and launch results.

- [ ] **Step 2: Exercise every phone surface**

Click through Today, Inbox, Runs, Projects, Settings, nested back/close controls, task create/edit/complete/delete confirmation, project creation, quick capture, voice permission/cancel/error paths, deep links, App Shortcuts, and the Share Extension.

- [ ] **Step 3: Verify failure recovery**

Exercise offline capture and recovery without deleting real production tasks. Confirm the UI reports unavailable CloudKit/voice conditions instead of silently claiming success.

- [ ] **Step 4: Deploy or confirm production CloudKit schema**

Inspect the development and production schema for `iCloud.com.tadies.ShipBar`; deploy the required schema to production through the CloudKit Console if it is not already present.

- [ ] **Step 5: Observe both sync directions**

Create a uniquely named harmless task on iPhone and observe it on Mac, then create another on Mac and observe it on iPhone. Remove only these named QA fixtures afterward and add timestamps/results to the HTML report.

### Task 5: Internal-only TestFlight delivery

**Files:**
- Create: `Config/iOS/ExportOptions.plist`
- Modify: `docs/reviews/2026-07-14-ios-testflight-verification.html`

**Interfaces:**
- Consumes: verified archive, team `5986DKD528`, bundle `com.tadies.ShipBar`, production CloudKit schema.
- Produces: processed internal TestFlight build assigned only to the owner's internal group and installable on the owner's phone.

- [ ] **Step 1: Add internal-TestFlight export policy**

Create an export options plist using Xcode 26.4's supported App Store Connect distribution keys, automatic signing, upload-symbols enabled, and `testFlightInternalTestingOnly = true` when supported by the installed Xcode.

- [ ] **Step 2: Confirm App Store Connect record and unique build**

Confirm or create the ShipBar app record for `com.tadies.ShipBar`, find the highest existing build number, and set the project build to the next integer before producing the final archive.

- [ ] **Step 3: Validate and upload**

Archive the final build, validate it, and upload with Xcode's organizer/export pipeline or `xcodebuild -exportArchive -allowProvisioningUpdates`. Record the upload identifier and any actionable validation errors.

- [ ] **Step 4: Process and assign privately**

Wait for Apple processing. Resolve compliance prompts, create or reuse an internal tester group, ensure its only tester is the owner, and assign the processed build with What to Test text covering capture, share, sync, and navigation.

- [ ] **Step 5: Install from TestFlight and close the gate**

Confirm the build appears in the owner's TestFlight app, install it, perform first launch with real data, and update the HTML report. Commit and push the final implementation only after the evidence distinguishes completed gates from Apple-side pending gates.
