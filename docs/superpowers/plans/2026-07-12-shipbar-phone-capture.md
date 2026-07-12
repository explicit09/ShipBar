# ShipBar Phone Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn ChatGPT output into a reviewed, structured ShipBar task through Share, Shortcuts, Siri, or the Action button without a ShipBar model API call.

**Architecture:** Add a tolerant structured-capture parser shared by every entry point, show a compact Share Extension preview, and route App Intents through the same durable queue contract from the sync foundation.

**Tech Stack:** Swift 6, UIKit, SwiftUI, AppIntents, Foundation, Swift Testing, iOS 17.

## Global Constraints

- Raw shared text is always preserved.
- Empty titles are rejected; unknown projects remain Inbox.
- Saving reports `Queued for ShipBar`, never false `Synced` status.
- All entry points use one parser and queue writer.
- No OpenAI Platform API call is introduced.

---

### Task 1: Structured ShipBar capture parser

**Files:**
- Create: `Sources/Shared/Capture/StructuredCaptureParser.swift`
- Modify: `Sources/Shared/Capture/CaptureParser.swift`
- Create: `Tests/ShipBarTests/StructuredCaptureParserTests.swift`

**Interfaces:**
- Produces: `StructuredCaptureParser.parse(_:projects:) -> CaptureDraft?`.

- [ ] Add failing tests for the approved `# ShipBar Task` format, multiline description, bullet acceptance criteria, agent prompt, missing optional fields, unknown project, empty title, CRLF input, and fallback to the existing shorthand parser.
- [ ] Verify RED.
- [ ] Implement a line-oriented parser with exact headings `Description:`, `Acceptance Criteria:`, and `Agent Prompt:`. Store acceptance criteria in the description under an `Acceptance Criteria` subheading and agent instructions in `prompt`.
- [ ] Make `SharedCapturePayload.captureDraft` try the structured parser before the shorthand parser.
- [ ] Run focused and full tests; commit `feat: parse structured ChatGPT captures`.

### Task 2: Share Extension review sheet

**Files:**
- Modify: `Sources/ShareExtension/ShipBarShareViewController.swift`
- Create: `Sources/ShareExtension/ShipBarSharePreviewView.swift`
- Modify: `project.yml`
- Create: `Tests/ShipBarTests/ShareExtensionContractTests.swift`

- [ ] Add failing source contracts requiring preview-before-save, explicit Save and Cancel actions, title/project/priority/prompt-readiness fields, and `Queued for ShipBar` confirmation.
- [ ] Verify RED.
- [ ] Replace save-on-appear with a SwiftUI-hosted compact preview. Load the provider once, parse it, allow title correction, and disable Save for an empty title.
- [ ] On Save, append the original payload plus normalized structured text to the App Group queue; on Cancel, complete without writing.
- [ ] Build the signed extension and verify from the ChatGPT iOS Share Sheet; commit `feat: review shared tasks before queueing`.

### Task 3: App Intents and Shortcuts

**Files:**
- Create: `Sources/iOS/Intents/CaptureInShipBarIntent.swift`
- Create: `Sources/iOS/Intents/OpenShipBarDestinationIntents.swift`
- Create: `Sources/iOS/Intents/ShipBarShortcutsProvider.swift`
- Modify: `Config/iOS/Info.plist`
- Test: `Tests/ShipBarTests/AppIntentContractTests.swift`

**Interfaces:**
- Produces: `CaptureInShipBarIntent`, `ShowShipBarInboxIntent`, `ShowFlightPlanIntent`, `PrepareTaskForCodexIntent`.

- [ ] Add failing source contracts for intent titles, parameters, queue usage, deep-link destinations, and non-empty validation.
- [ ] Verify RED.
- [ ] Implement `CaptureInShipBarIntent` with `text` and optional `sourceURL`; queue the capture and return a dialog containing its UUID. Implement navigation intents using `shipbar://inbox`, `shipbar://today`, and `shipbar://task/<id>/prepare`.
- [ ] Register suggested phrases in `AppShortcutsProvider` and URL handling in the iOS root.
- [ ] Build on a real device, run each intent from Shortcuts, Siri, and the Action button where available; commit `feat: add ShipBar capture intents`.

### Task 4: Phone capture acceptance

- [ ] Ask ChatGPT to emit the approved structured format, share it, edit the preview, and queue it while ShipBar is closed.
- [ ] Verify import contains title, description, criteria, prompt, project, priority, source URL, and raw text.
- [ ] Verify the equivalent Shortcut produces the same `CaptureDraft` and one task.
- [ ] Create `docs/reviews/shipbar-phone-capture-verification.html` with screenshots and exact results.
- [ ] Commit `docs: verify ChatGPT phone capture`.

