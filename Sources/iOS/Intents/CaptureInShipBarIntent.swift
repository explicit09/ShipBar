import AppIntents
import Foundation

struct CaptureInShipBarIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture in ShipBar"
    static let description = IntentDescription(
        "Queue text as a ShipBar task without opening the app. Structured '# ShipBar Task' text keeps its fields.")

    @Parameter(title: "Text") var text: String
    @Parameter(title: "Source URL") var sourceURL: URL?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = self.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw self.$text.needsValueError("What should ShipBar capture?")
        }
        let payload = SharedCapturePayload(
            text: trimmed,
            sourceApp: "Shortcuts",
            sourceURL: self.sourceURL?.absoluteString ?? "")
        try SharedCaptureStore.appendToSharedContainer(payload)
        return .result(dialog: "Queued for ShipBar. Capture \(payload.id).")
    }
}
