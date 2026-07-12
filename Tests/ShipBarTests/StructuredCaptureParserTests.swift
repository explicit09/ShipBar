import Foundation
import Testing

@Suite("Structured capture parser")
struct StructuredCaptureParserTests {
    private let projects = [
        ProjectToken(id: "p-shipbar-v2", name: "ShipBar V2"),
        ProjectToken(id: "p-website", name: "Website"),
    ]

    private let approvedFormat = """
    # ShipBar Task
    Title: Improve onboarding completion
    Project: ShipBar V2
    Priority: High
    Type: Feature

    Description:
    Clarify the first-run path and remove unnecessary choices.

    Acceptance Criteria:
    - A new user reaches the Flight Plan without setup confusion.
    - Existing users keep their current data.

    Agent Prompt:
    Inspect the current onboarding flow, implement the approved design, and attach test evidence.
    """

    @Test("approved format parses every field")
    func approvedFormatParses() throws {
        let draft = try #require(StructuredCaptureParser.parse(self.approvedFormat, projects: self.projects))

        #expect(draft.title == "Improve onboarding completion")
        #expect(draft.projectID == "p-shipbar-v2")
        #expect(draft.priority == .high)
        #expect(draft.type == .feature)
        #expect(draft.taskDescription.contains("Clarify the first-run path"))
        #expect(draft.taskDescription.contains("Acceptance Criteria"))
        #expect(draft.taskDescription.contains("- A new user reaches the Flight Plan without setup confusion."))
        #expect(draft.prompt == "Inspect the current onboarding flow, implement the approved design, and attach test evidence.")
        #expect(draft.rawText == self.approvedFormat)
    }

    @Test("multiline description is preserved")
    func multilineDescription() throws {
        let input = """
        # ShipBar Task
        Title: Ship the docs

        Description:
        First paragraph.

        Second paragraph after a blank line.
        """
        let draft = try #require(StructuredCaptureParser.parse(input, projects: []))

        #expect(draft.taskDescription.contains("First paragraph."))
        #expect(draft.taskDescription.contains("Second paragraph after a blank line."))
    }

    @Test("missing optional fields fall back to defaults")
    func missingOptionalFields() throws {
        let input = """
        # ShipBar Task
        Title: Just a title
        """
        let draft = try #require(StructuredCaptureParser.parse(input, projects: self.projects))

        #expect(draft.title == "Just a title")
        #expect(draft.projectID == nil)
        #expect(draft.priority == .medium)
        #expect(draft.type == .idea)
        #expect(draft.taskDescription.isEmpty)
        #expect(draft.prompt.isEmpty)
    }

    @Test("unknown project stays in inbox")
    func unknownProject() throws {
        let input = """
        # ShipBar Task
        Title: Mystery work
        Project: Not A Real Project
        """
        let draft = try #require(StructuredCaptureParser.parse(input, projects: self.projects))

        #expect(draft.projectID == nil)
    }

    @Test("empty title is rejected")
    func emptyTitleRejected() {
        let input = """
        # ShipBar Task
        Title:
        Priority: High
        """
        #expect(StructuredCaptureParser.parse(input, projects: self.projects) == nil)
    }

    @Test("CRLF input parses like LF input")
    func crlfInput() throws {
        let input = self.approvedFormat.replacingOccurrences(of: "\n", with: "\r\n")
        let draft = try #require(StructuredCaptureParser.parse(input, projects: self.projects))

        #expect(draft.title == "Improve onboarding completion")
        #expect(draft.projectID == "p-shipbar-v2")
        #expect(draft.prompt.hasPrefix("Inspect the current onboarding flow"))
    }

    @Test("unstructured text is not claimed by the structured parser")
    func unstructuredTextReturnsNil() {
        #expect(StructuredCaptureParser.parse("fix the login bug", projects: self.projects) == nil)
        #expect(StructuredCaptureParser.parse("", projects: self.projects) == nil)
    }

    @Test("shared payload prefers structured parsing")
    func sharedPayloadUsesStructuredParser() {
        let payload = SharedCapturePayload(
            id: "structured-1",
            text: self.approvedFormat,
            sourceApp: "ChatGPT",
            sourceURL: "https://chatgpt.com/c/example")
        let draft = payload.captureDraft(projects: self.projects)

        #expect(draft.title == "Improve onboarding completion")
        #expect(draft.projectID == "p-shipbar-v2")
        #expect(draft.priority == .high)
        #expect(draft.sourceApp == "ChatGPT")
        #expect(draft.sourceURL == "https://chatgpt.com/c/example")
        #expect(draft.rawText == self.approvedFormat)
        #expect(draft.sourceCaptureID == "structured-1")
    }

    @Test("shared payload falls back to shorthand parsing")
    func sharedPayloadFallsBack() {
        let payload = SharedCapturePayload(id: "shorthand-1", text: "website high update nav copy | Check the header links")
        let draft = payload.captureDraft(projects: self.projects)

        #expect(draft.title == "update nav copy")
        #expect(draft.projectID == "p-website")
        #expect(draft.priority == .high)
        #expect(draft.prompt == "Check the header links")
    }
}
