import Testing

@Suite("Capture parser")
struct CaptureParserTests {
    @Test("ignores blank batch capture")
    func ignoresBlankBatchCapture() {
        let results = CaptureBatchParser.parse(" \n\t ", projects: [])

        #expect(results.isEmpty)
    }

    @Test("parses project priority type and title before a colon")
    func parsesFullPrefix() {
        let projects = [ProjectToken(id: "vedit", name: "vedit")]

        let result = CaptureParser.parse("vedit high feature: Add undo stack", projects: projects)

        #expect(result.projectID == "vedit")
        #expect(result.priority == .high)
        #expect(result.type == .feature)
        #expect(result.title == "Add undo stack")
    }

    @Test("keeps raw input as title when prefix is unknown")
    func keepsUnknownPrefixAsTitle() {
        let result = CaptureParser.parse("unknown urgent thing", projects: [])

        #expect(result.projectID == nil)
        #expect(result.priority == .medium)
        #expect(result.type == .idea)
        #expect(result.title == "unknown urgent thing")
    }

    @Test("splits quick capture prompt after a pipe")
    func parsesPromptAfterPipe() {
        let projects = [ProjectToken(id: "vedit", name: "vedit")]

        let result = CaptureParser.parse(
            "vedit high feature: Add undo stack | Implement undo and redo with command boundaries.",
            projects: projects)

        #expect(result.title == "Add undo stack")
        #expect(result.prompt == "Implement undo and redo with command boundaries.")
    }

    @Test("parses status aliases before metadata")
    func parsesStatusAliases() {
        let projects = [ProjectToken(id: "learn-x", name: "LEARN-X")]

        let result = CaptureParser.parse("doing learnx high bug: Fix onboarding crash", projects: projects)

        #expect(result.projectID == "learn-x")
        #expect(result.status == .doing)
        #expect(result.priority == .high)
        #expect(result.type == .bug)
        #expect(result.title == "Fix onboarding crash")
    }

    @Test("captures source metadata after prompt")
    func parsesSourceMetadataAfterPrompt() {
        let result = CaptureParser.parse(
            "feature: Save Safari link | Turn this into a task @source=Safari @url=https://example.com/article",
            projects: [])

        #expect(result.title == "Save Safari link")
        #expect(result.prompt == "Turn this into a task")
        #expect(result.sourceApp == "Safari")
        #expect(result.sourceURL == "https://example.com/article")
    }

    @Test("parses shorthand project priority and type tokens")
    func parsesShorthandTokens() {
        let projects = [ProjectToken(id: "vedit", name: "vedit")]

        let result = CaptureParser.parse("#vedit ! fix: Repair export crash", projects: projects)

        #expect(result.projectID == "vedit")
        #expect(result.priority == .high)
        #expect(result.type == .bug)
        #expect(result.title == "Repair export crash")
    }

    @Test("turns multiline capture into title and prompt")
    func parsesMultilineCaptureAsPrompt() {
        let result = CaptureParser.parse(
            """
            Add prompt templates
            Make reusable Codex and Claude prompts with concise defaults.
            Keep the UI small.
            """,
            projects: [])

        #expect(result.title == "Add prompt templates")
        #expect(result.prompt.contains("reusable Codex and Claude prompts"))
        #expect(result.prompt.contains("Keep the UI small."))
    }

    @Test("parses AI-style numbered capture into multiple drafts")
    func parsesNumberedCaptureBatch() {
        let projects = [
            ProjectToken(id: "learn-x", name: "LEARN-X"),
            ProjectToken(id: "vedit", name: "vedit"),
        ]

        let results = CaptureBatchParser.parse(
            """
            Tomorrow:
            1. #learnx high feature: Tighten lesson recommendations
            2. #vedit p2 fix: Repair export crash
            3. Write launch notes
            """,
            projects: projects)

        #expect(results.count == 3)
        #expect(results[0].projectID == "learn-x")
        #expect(results[0].priority == .high)
        #expect(results[0].type == .feature)
        #expect(results[0].title == "Tighten lesson recommendations")
        #expect(results[1].projectID == "vedit")
        #expect(results[1].priority == .medium)
        #expect(results[1].type == .bug)
        #expect(results[1].title == "Repair export crash")
        #expect(results[2].title == "Write launch notes")
    }

    @Test("parses bullet capture into multiple drafts")
    func parsesBulletCaptureBatch() {
        let results = CaptureBatchParser.parse(
            """
            - Add voice intake
            - [ ] Add inbox review filters
            * Copy prompt to Codex
            """,
            projects: [])

        #expect(results.map(\.title) == [
            "Add voice intake",
            "Add inbox review filters",
            "Copy prompt to Codex",
        ])
    }
}
