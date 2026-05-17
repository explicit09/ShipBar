import Foundation
import Testing

@Suite("Shared capture store")
struct SharedCaptureStoreTests {
    @Test("payload converts shared text and URL into inbox draft")
    func payloadConvertsToInboxDraft() {
        let payload = SharedCapturePayload(
            text: "vedit high feature: Add share extension",
            sourceApp: "Safari",
            sourceURL: "https://example.com")
        let projects = [ProjectToken(id: "vedit", name: "vedit")]

        let draft = payload.captureDraft(projects: projects)

        #expect(draft.title == "Add share extension")
        #expect(draft.projectID == "vedit")
        #expect(draft.priority == .high)
        #expect(draft.type == .feature)
        #expect(draft.sourceApp == "Safari")
        #expect(draft.sourceURL == "https://example.com")
        #expect(draft.rawText.contains("Add share extension"))
    }

    @Test("consume returns captures once and clears file")
    func consumeReturnsCapturesOnceAndClearsFile() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let payload = SharedCapturePayload(text: "school: Essay outline", sourceApp: "Notes")

        try SharedCaptureStore.append(payload, to: fileURL)

        let firstRead = try SharedCaptureStore.consume(from: fileURL)
        let secondRead = try SharedCaptureStore.consume(from: fileURL)

        #expect(firstRead == [payload])
        #expect(secondRead.isEmpty)
    }
}
