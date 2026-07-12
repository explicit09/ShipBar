import Foundation

/// Atomic JSON envelope exchange under `<base>/Bridge/v1/{requests,responses}`.
/// Local-only transport between the signed helper and the running menu app.
struct ShipBarBridgeStore: Sendable {
    static let bridgeDirectoryName = "Bridge"

    private let requestsDirectory: URL
    private let responsesDirectory: URL

    init(baseDirectory: URL) throws {
        let versionDirectory = baseDirectory
            .appendingPathComponent(Self.bridgeDirectoryName)
            .appendingPathComponent("v\(ShipBarBridgeSchema.version)")
        self.requestsDirectory = versionDirectory.appendingPathComponent("requests")
        self.responsesDirectory = versionDirectory.appendingPathComponent("responses")
        try FileManager.default.createDirectory(at: self.requestsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: self.responsesDirectory, withIntermediateDirectories: true)
    }

    /// The App Group container must be created by the sandboxed ShipBar
    /// app, not by the unsandboxed helper. If the helper creates it
    /// first, containermanagerd records the helper as its creator and
    /// never provisions it for the app, whose directory reads then hang
    /// forever. `requireExistingContainer` lets the helper refuse to be
    /// the creator.
    static func appGroup(requireExistingContainer: Bool = false) throws -> ShipBarBridgeStore {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedCaptureStore.appGroupIdentifier)
        else {
            throw SharedCaptureStoreError.sharedContainerUnavailable(
                appGroupIdentifier: SharedCaptureStore.appGroupIdentifier)
        }
        if requireExistingContainer {
            let bridgeRoot = containerURL
                .appendingPathComponent(Self.bridgeDirectoryName)
                .appendingPathComponent("v\(ShipBarBridgeSchema.version)")
            guard FileManager.default.fileExists(atPath: bridgeRoot.path) else {
                throw ShipBarBridgeError.bridgeNotReady
            }
        }
        return try ShipBarBridgeStore(baseDirectory: containerURL)
    }

    /// The resolved requests directory, for diagnostics only.
    var debugRootPath: String {
        self.requestsDirectory.path
    }

    @discardableResult
    func append(_ request: ShipBarBridgeRequest) throws -> Bool {
        let fileURL = self.requestURL(id: request.id)
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return false }
        let data = try JSONEncoder().encode(request)
        try data.write(to: fileURL, options: [.atomic])
        return true
    }

    func pendingRequests() throws -> [ShipBarBridgeRequest] {
        try self.envelopes(ShipBarBridgeRequest.self, in: self.requestsDirectory)
            .sorted { $0.createdAt < $1.createdAt }
    }

    func removeRequest(id: String) throws {
        let fileURL = self.requestURL(id: id)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    func writeResponse(_ response: ShipBarBridgeResponse) throws {
        let data = try JSONEncoder().encode(response)
        try data.write(to: self.responseURL(requestID: response.requestID), options: [.atomic])
    }

    func response(for requestID: String) throws -> ShipBarBridgeResponse? {
        let fileURL = self.responseURL(requestID: requestID)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try JSONDecoder().decode(ShipBarBridgeResponse.self, from: Data(contentsOf: fileURL))
    }

    func removeResponse(requestID: String) throws {
        let fileURL = self.responseURL(requestID: requestID)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    func waitForResponse(
        requestID: String,
        timeout: TimeInterval,
        pollInterval: TimeInterval = 0.2) async throws -> ShipBarBridgeResponse?
    {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let response = try self.response(for: requestID) {
                return response
            }
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
        return try self.response(for: requestID)
    }

    static func validateEvidencePaths(_ paths: [String], approvedRoots: [String]) -> Bool {
        guard !paths.isEmpty else { return true }
        let roots = approvedRoots.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
        return paths.allSatisfy { path in
            let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
            return roots.contains { root in
                standardized == root || standardized.hasPrefix(root + "/")
            }
        }
    }

    private func requestURL(id: String) -> URL {
        self.requestsDirectory.appendingPathComponent("\(id).json")
    }

    private func responseURL(requestID: String) -> URL {
        self.responsesDirectory.appendingPathComponent("\(requestID).json")
    }

    private func envelopes<T: Decodable>(_ type: T.Type, in directory: URL) throws -> [T] {
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        return files.compactMap { fileURL in
            guard let data = try? Data(contentsOf: fileURL) else { return nil }
            return try? JSONDecoder().decode(type, from: data)
        }
    }
}
