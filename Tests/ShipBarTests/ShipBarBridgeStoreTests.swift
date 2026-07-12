import Foundation
import Testing

@Suite("ShipBar bridge protocol and store")
struct ShipBarBridgeStoreTests {
    private func makeStore() throws -> ShipBarBridgeStore {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("shipbar-bridge-tests-\(UUID().uuidString)")
        return try ShipBarBridgeStore(baseDirectory: base)
    }

    @Test("request envelopes round-trip through the store")
    func requestRoundTrip() throws {
        let store = try self.makeStore()
        let request = ShipBarBridgeRequest(command: .requestReview(
            runID: "run-1",
            summary: "Implemented and verified",
            evidencePaths: ["/tmp/evidence.html"]))

        #expect(try store.append(request))
        let pending = try store.pendingRequests()
        #expect(pending == [request])
    }

    @Test("every closed command round-trips")
    func commandsRoundTrip() throws {
        let commands: [ShipBarBridgeCommand] = [
            .listPrepared,
            .getContext(runID: "r"),
            .claim(runID: "r"),
            .markRunning(runID: "r"),
            .requestReview(runID: "r", summary: "s", evidencePaths: ["/tmp/a"]),
            .markFailed(runID: "r", message: "m"),
            .cancel(runID: "r", message: "m"),
        ]
        for command in commands {
            let data = try JSONEncoder().encode(ShipBarBridgeRequest(command: command))
            let decoded = try JSONDecoder().decode(ShipBarBridgeRequest.self, from: data)
            #expect(decoded.command == command)
        }
    }

    @Test("unknown schema versions are rejected")
    func unknownSchemaRejected() throws {
        let json = """
        {"id":"x","schemaVersion":99,"createdAt":0,"command":{"type":"listPrepared"}}
        """
        #expect(throws: Error.self) {
            try JSONDecoder().decode(ShipBarBridgeRequest.self, from: Data(json.utf8))
        }
    }

    @Test("unknown command types are rejected")
    func unknownCommandRejected() throws {
        let json = """
        {"id":"x","schemaVersion":1,"createdAt":0,"command":{"type":"runShellCommand","script":"rm -rf /"}}
        """
        #expect(throws: Error.self) {
            try JSONDecoder().decode(ShipBarBridgeRequest.self, from: Data(json.utf8))
        }
    }

    @Test("duplicate request IDs are ignored")
    func duplicateRequestsIgnored() throws {
        let store = try self.makeStore()
        let request = ShipBarBridgeRequest(command: .listPrepared)

        #expect(try store.append(request))
        #expect(try !store.append(request))
        #expect(try store.pendingRequests().count == 1)
    }

    @Test("responses resolve waiting callers and time out otherwise")
    func responseWaitAndTimeout() async throws {
        let store = try self.makeStore()
        let request = ShipBarBridgeRequest(command: .claim(runID: "run-9"))
        _ = try store.append(request)

        let missing = try await store.waitForResponse(
            requestID: request.id,
            timeout: 0.2,
            pollInterval: 0.05)
        #expect(missing == nil)

        let response = ShipBarBridgeResponse.success(requestID: request.id, result: .acknowledged)
        try store.writeResponse(response)
        let found = try await store.waitForResponse(
            requestID: request.id,
            timeout: 1,
            pollInterval: 0.05)
        #expect(found == response)
    }

    @Test("processed requests can be removed")
    func processedRequestsRemoved() throws {
        let store = try self.makeStore()
        let request = ShipBarBridgeRequest(command: .listPrepared)
        _ = try store.append(request)

        try store.removeRequest(id: request.id)
        #expect(try store.pendingRequests().isEmpty)
    }

    @Test("concurrent distinct requests all persist")
    func concurrentRequestsPersist() async throws {
        let store = try self.makeStore()
        let requests = (0 ..< 8).map { _ in ShipBarBridgeRequest(command: .listPrepared) }

        await withTaskGroup(of: Void.self) { group in
            for request in requests {
                group.addTask {
                    _ = try? store.append(request)
                }
            }
        }

        #expect(try store.pendingRequests().count == requests.count)
    }

    @Test("evidence paths outside approved roots are rejected")
    func evidencePathValidation() {
        let roots = ["/Users/me/Projects/ShipBar/docs/reviews"]

        #expect(ShipBarBridgeStore.validateEvidencePaths(
            ["/Users/me/Projects/ShipBar/docs/reviews/run-1.html"],
            approvedRoots: roots))
        #expect(!ShipBarBridgeStore.validateEvidencePaths(
            ["/Users/me/Projects/ShipBar/docs/reviews/../../../../etc/passwd"],
            approvedRoots: roots))
        #expect(!ShipBarBridgeStore.validateEvidencePaths(
            ["/private/tmp/unrelated.html"],
            approvedRoots: roots))
        #expect(!ShipBarBridgeStore.validateEvidencePaths(
            ["/Users/me/Projects/ShipBar/docs/reviews-evil/run.html"],
            approvedRoots: roots))
    }
}
