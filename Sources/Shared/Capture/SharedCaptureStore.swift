import Foundation

struct SharedCapturePayload: Codable, Equatable, Identifiable {
    static let currentSchemaVersion = 1

    var id: String
    var schemaVersion: Int
    var text: String
    var sourceApp: String
    var sourceURL: String
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        schemaVersion: Int = Self.currentSchemaVersion,
        text: String,
        sourceApp: String = "",
        sourceURL: String = "",
        createdAt: Date = .now)
    {
        self.id = id
        self.schemaVersion = schemaVersion
        self.text = text
        self.sourceApp = sourceApp
        self.sourceURL = sourceURL
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, schemaVersion, text, sourceApp, sourceURL, createdAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try values.decode(String.self, forKey: .id)
        self.schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.text = try values.decode(String.self, forKey: .text)
        self.sourceApp = try values.decodeIfPresent(String.self, forKey: .sourceApp) ?? ""
        self.sourceURL = try values.decodeIfPresent(String.self, forKey: .sourceURL) ?? ""
        self.createdAt = try values.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
    }

    func captureDraft(projects: [ProjectToken]) -> CaptureDraft {
        let trimmedText = self.text.trimmingCharacters(in: .whitespacesAndNewlines)
        var parserInput = trimmedText
        let sourceMarkers = self.sourceMarkers
        if !sourceMarkers.isEmpty {
            parserInput += " | \(sourceMarkers)"
        }

        var draft = CaptureParser.parse(parserInput, projects: projects)
        if draft.title.isEmpty, !self.sourceURL.isEmpty {
            draft.title = self.sourceURL
        }
        if draft.sourceApp.isEmpty {
            draft.sourceApp = self.sourceApp
        }
        if draft.sourceURL.isEmpty {
            draft.sourceURL = self.sourceURL
        }
        draft.rawText = trimmedText
        return draft
    }

    private var sourceMarkers: String {
        [
            self.sourceApp.isEmpty ? nil : "@source=\(self.sourceApp)",
            self.sourceURL.isEmpty ? nil : "@url=\(self.sourceURL)",
        ]
            .compactMap(\.self)
            .joined(separator: " ")
    }
}

enum SharedCaptureStore {
    static let appGroupIdentifier = "group.com.tadies.ShipBar"
    static let fileName = "PendingCaptures.json"

    static var diagnostics: SharedCaptureDiagnostics {
        let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier)
        return SharedCaptureDiagnostics(
            appGroupIdentifier: Self.appGroupIdentifier,
            isContainerAvailable: containerURL != nil)
    }

    static func append(_ payload: SharedCapturePayload, to fileURL: URL) throws {
        var captures = try Self.load(from: fileURL)
        guard !captures.contains(where: { $0.id == payload.id }) else { return }
        captures.append(payload)
        try Self.save(captures, to: fileURL)
    }

    static func pending(from fileURL: URL) throws -> [SharedCapturePayload] {
        try Self.load(from: fileURL)
    }

    static func acknowledge(_ ids: Set<String>, from fileURL: URL) throws {
        guard !ids.isEmpty else { return }
        let remaining = try Self.load(from: fileURL).filter { !ids.contains($0.id) }
        try Self.save(remaining, to: fileURL)
    }

    static func consume(from fileURL: URL) throws -> [SharedCapturePayload] {
        let captures = try Self.pending(from: fileURL)
        guard !captures.isEmpty else { return [] }
        try Self.acknowledge(Set(captures.map(\.id)), from: fileURL)
        return captures
    }

    static func appendToSharedContainer(_ payload: SharedCapturePayload) throws {
        guard let fileURL = Self.sharedFileURL() else {
            throw SharedCaptureStoreError.sharedContainerUnavailable(
                appGroupIdentifier: Self.appGroupIdentifier)
        }
        try Self.append(payload, to: fileURL)
    }

    static func consumeFromSharedContainer() throws -> [SharedCapturePayload] {
        guard let fileURL = Self.sharedFileURL() else {
            throw SharedCaptureStoreError.sharedContainerUnavailable(
                appGroupIdentifier: Self.appGroupIdentifier)
        }
        return try Self.consume(from: fileURL)
    }

    static func pendingFromSharedContainer() throws -> [SharedCapturePayload] {
        guard let fileURL = Self.sharedFileURL() else {
            throw SharedCaptureStoreError.sharedContainerUnavailable(
                appGroupIdentifier: Self.appGroupIdentifier)
        }
        return try Self.pending(from: fileURL)
    }

    static func acknowledgeFromSharedContainer(_ ids: Set<String>) throws {
        guard let fileURL = Self.sharedFileURL() else {
            throw SharedCaptureStoreError.sharedContainerUnavailable(
                appGroupIdentifier: Self.appGroupIdentifier)
        }
        try Self.acknowledge(ids, from: fileURL)
    }

    static func load(from fileURL: URL) throws -> [SharedCapturePayload] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return [] }
        return try JSONDecoder().decode([SharedCapturePayload].self, from: data)
    }

    private static func save(_ captures: [SharedCapturePayload], to fileURL: URL) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(captures)
        try data.write(to: fileURL, options: [.atomic])
    }

    private static func sharedFileURL() -> URL? {
        let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier)
        return containerURL?.appendingPathComponent(Self.fileName)
    }
}

enum SharedCaptureStoreError: LocalizedError, Equatable {
    case sharedContainerUnavailable(appGroupIdentifier: String)

    var errorDescription: String? {
        switch self {
        case let .sharedContainerUnavailable(appGroupIdentifier):
            "ShipBar cannot access the App Group container \(appGroupIdentifier). Check entitlements and signing."
        }
    }
}

struct SharedCaptureDiagnostics: Equatable {
    let appGroupIdentifier: String
    let isContainerAvailable: Bool

    var statusText: String {
        self.isContainerAvailable ? "Available" : "Unavailable in this run"
    }

    var detailText: String {
        self.isContainerAvailable
            ? "Share Extension can write into \(self.appGroupIdentifier)."
            : "App Group access needs a signed app/extension build using \(self.appGroupIdentifier)."
    }
}
