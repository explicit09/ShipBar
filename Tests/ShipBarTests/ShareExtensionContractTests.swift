import Foundation
import Testing

@Suite("Share extension source contracts")
struct ShareExtensionContractTests {
    @Test("controller previews before saving instead of writing on appear")
    func controllerPreviewsBeforeSaving() throws {
        let controller = try self.source("Sources/ShareExtension/ShipBarShareViewController.swift")

        #expect(controller.contains("ShipBarSharePreviewView"))
        #expect(controller.contains("UIHostingController"))
        #expect(!controller.contains("appendToSharedContainer"))
        #expect(!controller.contains("Saving to ShipBar"))
    }

    @Test("preview offers explicit save and cancel with review fields")
    func previewOffersSaveAndCancel() throws {
        let preview = try self.source("Sources/ShareExtension/ShipBarSharePreviewView.swift")

        #expect(preview.contains("Queued for ShipBar"))
        #expect(preview.contains("Cancel"))
        #expect(preview.contains("SharedCaptureStore.appendToSharedContainer"))
        #expect(preview.contains("TextField"))
        #expect(preview.contains(".disabled"))
        #expect(preview.contains("projectHint"))
        #expect(preview.contains("priority"))
        #expect(preview.contains("prompt"))
    }

    @Test("normalized structured text carries title corrections while raw text is preserved")
    func normalizedTextCarriesCorrections() {
        let raw = """
        # ShipBar Task
        Title: Original title
        Project: ShipBar V2
        Priority: High

        Agent Prompt:
        Do the thing.
        """
        let projects = [ProjectToken(id: "p-shipbar-v2", name: "ShipBar V2")]
        var draft = StructuredCaptureParser.parse(raw, projects: []) ?? CaptureDraft(
            title: "",
            prompt: "",
            projectID: nil,
            status: .todo,
            priority: .medium,
            type: .idea,
            dueDate: nil,
            sourceApp: "",
            sourceURL: "",
            rawText: raw)
        draft.title = "Corrected title"

        let payload = SharedCapturePayload(
            id: "edited-1",
            text: raw,
            normalizedText: StructuredCaptureParser.normalizedText(from: draft))
        let imported = payload.captureDraft(projects: projects)

        #expect(imported.title == "Corrected title")
        #expect(imported.projectID == "p-shipbar-v2")
        #expect(imported.priority == .high)
        #expect(imported.prompt == "Do the thing.")
        #expect(imported.rawText == raw)
        #expect(imported.sourceCaptureID == "edited-1")
    }

    @Test("payloads without normalized text keep legacy parsing")
    func legacyPayloadsStillParse() throws {
        let json = """
        [{"id":"legacy-2","text":"plain capture text","createdAt":0}]
        """
        let decoded = try JSONDecoder().decode([SharedCapturePayload].self, from: Data(json.utf8))
        let payload = try #require(decoded.first)

        #expect(payload.normalizedText.isEmpty)
        #expect(payload.captureDraft(projects: []).title == "plain capture text")
    }

    private func source(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
