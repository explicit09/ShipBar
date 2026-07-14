# ShipBar iOS Internal TestFlight Design

**Date:** 2026-07-14
**Status:** Approved for planning after written-spec review

## Goal

Deliver a complete, private ShipBar iPhone beta to the owner's App Store Connect account through internal-only TestFlight. The build must be useful on the phone by itself, synchronize truthfully with the existing Mac app, and expose the capture surfaces that make mobile valuable.

This is the first of two ordered ShipBar slices. The next slice extends the hosted relay and MCP surface for normal ChatGPT conversations. It starts only after the iPhone build is uploaded and its remaining Apple-side gates are explicit.

## Current Baseline

The live audit established that:

- Xcode 26.4 and the iOS 26.4 SDK are installed;
- the paired iPhone 15 Pro Max is visible to Xcode;
- simulator and signed Release device builds succeed;
- a Release archive succeeds with bundle ID `com.tadies.ShipBar`;
- the archive embeds `ShipBarShareExtension.appex`;
- App Intents, shortcuts metadata, CloudKit, App Groups, deep links, and voice code are present;
- the archive is development-signed and is not yet an App Store distribution artifact;
- the app has no asset catalog or App Store icon;
- version metadata conflicts between `project.yml` and `Config/iOS/Info.plist`;
- the archive reports an orientation warning;
- CloudKit production-schema readiness and App Store Connect app-record readiness are unproven.

## Product Scope

### Private distribution

The first build is internal TestFlight for one tester: the owner. It is not submitted for external beta review or App Store review. The app targets iPhone for this first beta; iPad-specific layout and external tester readiness are deferred.

The release identity is:

- Display name: `ShipBar`
- Bundle ID: `com.tadies.ShipBar`
- Marketing version: `1.0`
- Build number: a monotonically increasing integer, starting with the next uploadable value
- Device family: iPhone
- Minimum iOS version: iOS 17

### Mobile capability contract

The beta must expose and verify:

- Today and Flight Plan;
- Inbox triage;
- Projects and project creation/editing;
- run status and review surfaces;
- task detail editing, completion, deletion confirmation, scheduling, project assignment, and agent handoff preparation;
- quick capture and voice capture;
- Share Extension capture from text and URLs with a preview-before-save step;
- App Shortcuts/App Intents for capture, Inbox, Flight Plan, and Codex preparation;
- `shipbar://` deep links;
- CloudKit synchronization in both directions between iPhone and Mac;
- truthful offline/error state when CloudKit or voice services are unavailable.

The iPhone prepares Codex work for a Mac. It must never claim that a desktop agent started until a Mac device actually claims and reports the run.

## Store-Readiness Changes

### Brand assets

Add a production asset catalog with a complete single-size iOS App Icon. The icon will follow ShipBar's established graphite-and-signal visual language: a dark graphite field, a simple original route/ship mark, and one blue-violet signal accent. It must remain legible at Settings and Spotlight sizes and must not reuse an SF Symbol as the distributable artwork.

### Metadata and platform configuration

- Make Xcode build settings the single source of version truth and remove conflicting hard-coded values.
- Target iPhone for the first beta to eliminate unsupported iPad-orientation expectations.
- Declare portrait plus both landscape orientations for iPhone unless hands-on QA proves a specific surface unsafe in landscape.
- Add `ITSAppUsesNonExemptEncryption = false` because ShipBar uses platform-provided transport encryption and does not implement non-exempt cryptography.
- Add a privacy manifest that truthfully describes tracking, collected data, and required-reason API use. Do not claim that voice or task content stays on-device when it is sent to configured services.
- Preserve CloudKit, push, App Group, microphone, URL scheme, and Share Extension entitlements.

### CloudKit

TestFlight uses the production CloudKit environment. Before distribution:

1. launch and exercise the development build against the development container;
2. inspect the container schema;
3. deploy the required schema to production;
4. install the TestFlight build and prove a real phone-to-Mac and Mac-to-phone round trip;
5. record failures truthfully instead of falling back silently to an in-memory store.

## Distribution Flow

1. Create or confirm the App Store Connect app record for `com.tadies.ShipBar`.
2. Create distribution signing and provisioning through Xcode automatic signing.
3. archive the Release build with a unique build number;
4. validate and upload it as TestFlight internal-only;
5. wait for Apple processing and resolve any invalid-binary or missing-compliance errors;
6. create or reuse an internal group with automatic distribution;
7. add only the owner's App Store Connect user;
8. add concise What to Test text covering capture, share, sync, and navigation;
9. confirm the build appears in TestFlight and is installable by the owner.

Uploading a build is not the same as confirming phone availability. Completion requires the processed build to be assigned to the internal tester group.

## Verification

### Automated and build proof

- full macOS Swift test suite passes;
- focused iOS contract tests cover assets, metadata, entitlements, the embedded extension, App Intents, and deep-link configuration;
- iOS simulator build passes;
- signed Release device build passes;
- Release archive contains the application, Share Extension, App Intents metadata, icons, privacy manifest, and distribution entitlements;
- App Store validation/upload succeeds.

### Hands-on proof

Use isolated/fixture data for destructive UI testing, then real CloudKit data for sync proof. Verify:

- all five destinations and every visible back/close path;
- compact and large Dynamic Type where practical;
- portrait and landscape layouts;
- quick capture, task editing, project creation, and deletion confirmation;
- voice permission, start, cancel, success, and unavailable-key behavior;
- Share Extension from Safari/text content;
- App Shortcuts and deep links;
- offline capture followed by recovery;
- phone-to-Mac and Mac-to-phone synchronization;
- TestFlight installation and first real-data launch.

## Safety and Truth Boundaries

- Do not submit the app for public App Review.
- Do not invite external testers.
- Do not delete production tasks during QA.
- Do not expose API keys in the app bundle, logs, screenshots, or review artifacts.
- Do not call a build TestFlight-ready until Apple finishes processing it.
- Do not call CloudKit sync ready until the production container round trip is observed.

## Deferred Work

- iPad-specific design;
- external TestFlight and public App Store submission;
- public privacy-policy and marketing pages;
- normal-chat ShipBar CRUD through a published ChatGPT app;
- Windows execution support.
