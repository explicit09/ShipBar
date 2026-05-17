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
}
