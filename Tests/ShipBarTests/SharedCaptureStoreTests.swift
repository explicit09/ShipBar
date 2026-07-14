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
        #expect(draft.sourceCaptureID == payload.id)
    }

    @Test("import selection skips capture ids already saved as tasks")
    func importerSkipsSavedCaptureIDs() {
        let first = SharedCapturePayload(id: "capture-1", text: "First")
        let second = SharedCapturePayload(id: "capture-2", text: "Second")

        let missing = SharedCaptureImporter.missingCaptures(
            [first, second],
            existingCaptureIDs: ["capture-1", ""])

        #expect(missing == [second])
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

    @Test("pending reads do not delete queued captures")
    func pendingReadsAreNonDestructive() throws {
        let fileURL = self.temporaryFileURL()
        let payload = SharedCapturePayload(id: "capture-1", text: "Draft launch notes")
        try SharedCaptureStore.append(payload, to: fileURL)

        #expect(try SharedCaptureStore.pending(from: fileURL) == [payload])
        #expect(try SharedCaptureStore.pending(from: fileURL) == [payload])
    }

    @Test("acknowledging one capture preserves the rest")
    func acknowledgePreservesOtherCaptures() throws {
        let fileURL = self.temporaryFileURL()
        let first = SharedCapturePayload(id: "capture-1", text: "First")
        let second = SharedCapturePayload(id: "capture-2", text: "Second")
        try SharedCaptureStore.append(first, to: fileURL)
        try SharedCaptureStore.append(second, to: fileURL)

        try SharedCaptureStore.acknowledge([first.id], from: fileURL)

        #expect(try SharedCaptureStore.pending(from: fileURL) == [second])
    }

    @Test("appending the same capture id is idempotent")
    func duplicateAppendIsIgnored() throws {
        let fileURL = self.temporaryFileURL()
        let payload = SharedCapturePayload(id: "capture-1", text: "Only once")

        try SharedCaptureStore.append(payload, to: fileURL)
        try SharedCaptureStore.append(payload, to: fileURL)

        #expect(try SharedCaptureStore.pending(from: fileURL) == [payload])
    }

    @Test("legacy payloads decode as schema version one")
    func legacyPayloadSchemaVersion() throws {
        let json = #"{"id":"legacy","text":"Old capture","sourceApp":"","sourceURL":"","createdAt":0}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        let payload = try decoder.decode(SharedCapturePayload.self, from: Data(json.utf8))

        #expect(payload.schemaVersion == 1)
        #expect(payload.state == .queued)
        #expect(payload.attemptCount == 0)
        #expect(payload.lastAttemptAt == nil)
        #expect(payload.userReadableError == "")
    }

    @Test("failed captures preserve diagnostics and can be retried")
    func failureAndRetryTransitions() throws {
        let fileURL = self.temporaryFileURL()
        let payload = SharedCapturePayload(id: "capture-1", text: "Retry me")
        try SharedCaptureStore.append(payload, to: fileURL)

        try SharedCaptureStore.beginAttempt(payload.id, from: fileURL, at: Date(timeIntervalSince1970: 10))
        try SharedCaptureStore.markFailed(payload.id, error: "ShipBar could not save this capture.", from: fileURL)
        let failedEnvelope = try SharedCaptureStore.envelope(payload.id, from: fileURL)
        let failed = try #require(failedEnvelope)
        #expect(failed.state == .failed)
        #expect(failed.attemptCount == 1)
        #expect(failed.lastAttemptAt == Date(timeIntervalSince1970: 10))
        #expect(failed.userReadableError == "ShipBar could not save this capture.")

        try SharedCaptureStore.retry(payload.id, from: fileURL)
        let retriedEnvelope = try SharedCaptureStore.envelope(payload.id, from: fileURL)
        let retried = try #require(retriedEnvelope)
        #expect(retried.state == .queued)
        #expect(retried.attemptCount == 1)
        #expect(retried.userReadableError == "")
    }

    @Test("append racing acknowledge across store instances never loses the new capture")
    func appendAcknowledgeRace() async throws {
        let fileURL = self.temporaryFileURL()
        let existing = SharedCapturePayload(id: "existing", text: "Existing")
        let arriving = SharedCapturePayload(id: "arriving", text: "Arriving")
        try SharedCaptureStore.append(existing, to: fileURL)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<25 {
                group.addTask { try SharedCaptureStore.append(arriving, to: fileURL) }
                group.addTask { try SharedCaptureStore.acknowledge([existing.id], from: fileURL) }
            }
            try await group.waitForAll()
        }

        #expect(try SharedCaptureStore.pending(from: fileURL).map(\.id) == [arriving.id])
        #expect(try SharedCaptureStore.envelope(existing.id, from: fileURL)?.state == .imported)
    }

    @Test("shared container error includes app group identifier")
    func sharedContainerErrorIncludesAppGroupIdentifier() {
        let error = SharedCaptureStoreError.sharedContainerUnavailable(
            appGroupIdentifier: SharedCaptureStore.appGroupIdentifier)

        #expect(error.errorDescription?.contains(SharedCaptureStore.appGroupIdentifier) == true)
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    }
}
