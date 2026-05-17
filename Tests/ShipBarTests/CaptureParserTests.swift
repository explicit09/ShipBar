import Testing

@Suite("Capture parser")
struct CaptureParserTests {
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
}
