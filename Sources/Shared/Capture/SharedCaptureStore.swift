import Foundation

struct SharedCapturePayload: Codable, Equatable, Identifiable {
    var id: String
    var text: String
    var sourceApp: String
    var sourceURL: String
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        text: String,
        sourceApp: String = "",
        sourceURL: String = "",
        createdAt: Date = .now)
    {
        self.id = id
        self.text = text
        self.sourceApp = sourceApp
        self.sourceURL = sourceURL
        self.createdAt = createdAt
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

    static func append(_ payload: SharedCapturePayload, to fileURL: URL) throws {
        var captures = try Self.load(from: fileURL)
        captures.append(payload)
        try Self.save(captures, to: fileURL)
    }

    static func consume(from fileURL: URL) throws -> [SharedCapturePayload] {
        let captures = try Self.load(from: fileURL)
        guard !captures.isEmpty else { return [] }
        try Self.save([], to: fileURL)
        return captures
    }

    static func appendToSharedContainer(_ payload: SharedCapturePayload) throws {
        guard let fileURL = Self.sharedFileURL() else { return }
        try Self.append(payload, to: fileURL)
    }

    static func consumeFromSharedContainer() throws -> [SharedCapturePayload] {
        guard let fileURL = Self.sharedFileURL() else { return [] }
        return try Self.consume(from: fileURL)
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
