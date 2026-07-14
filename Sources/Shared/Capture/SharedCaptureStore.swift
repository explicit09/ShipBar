import Foundation
#if canImport(Darwin)
import Darwin
#endif

enum SharedCaptureState: String, Codable, Equatable, Sendable {
    case queued
    case imported
    case syncing
    case synced
    case failed
}

struct SharedCapturePayload: Codable, Equatable, Identifiable {
    static let currentSchemaVersion = 2

    var id: String
    var schemaVersion: Int
    var text: String
    var normalizedText: String
    var sourceApp: String
    var sourceURL: String
    var createdAt: Date
    var state: SharedCaptureState
    var attemptCount: Int
    var lastAttemptAt: Date?
    var userReadableError: String

    init(
        id: String = UUID().uuidString,
        schemaVersion: Int = Self.currentSchemaVersion,
        text: String,
        normalizedText: String = "",
        sourceApp: String = "",
        sourceURL: String = "",
        createdAt: Date = .now,
        state: SharedCaptureState = .queued,
        attemptCount: Int = 0,
        lastAttemptAt: Date? = nil,
        userReadableError: String = "")
    {
        self.id = id
        self.schemaVersion = schemaVersion
        self.text = text
        self.normalizedText = normalizedText
        self.sourceApp = sourceApp
        self.sourceURL = sourceURL
        self.createdAt = createdAt
        self.state = state
        self.attemptCount = attemptCount
        self.lastAttemptAt = lastAttemptAt
        self.userReadableError = userReadableError
    }

    private enum CodingKeys: String, CodingKey {
        case id, schemaVersion, text, normalizedText, sourceApp, sourceURL, createdAt
        case state, attemptCount, lastAttemptAt, userReadableError
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try values.decode(String.self, forKey: .id)
        self.schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.text = try values.decode(String.self, forKey: .text)
        self.normalizedText = try values.decodeIfPresent(String.self, forKey: .normalizedText) ?? ""
        self.sourceApp = try values.decodeIfPresent(String.self, forKey: .sourceApp) ?? ""
        self.sourceURL = try values.decodeIfPresent(String.self, forKey: .sourceURL) ?? ""
        self.createdAt = try values.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        self.state = try values.decodeIfPresent(SharedCaptureState.self, forKey: .state) ?? .queued
        self.attemptCount = try values.decodeIfPresent(Int.self, forKey: .attemptCount) ?? 0
        self.lastAttemptAt = try values.decodeIfPresent(Date.self, forKey: .lastAttemptAt)
        self.userReadableError = try values.decodeIfPresent(String.self, forKey: .userReadableError) ?? ""
    }

    func captureDraft(projects: [ProjectToken]) -> CaptureDraft {
        let trimmedText = self.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let structuredInput = self.normalizedText.isEmpty ? trimmedText : self.normalizedText
        if var structured = StructuredCaptureParser.parse(structuredInput, projects: projects) {
            if structured.sourceApp.isEmpty {
                structured.sourceApp = self.sourceApp
            }
            if structured.sourceURL.isEmpty {
                structured.sourceURL = self.sourceURL
            }
            structured.rawText = trimmedText
            structured.sourceCaptureID = self.id
            return structured
        }
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
        draft.sourceCaptureID = self.id
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

enum SharedCaptureImporter {
    static func missingCaptures(
        _ captures: [SharedCapturePayload],
        existingCaptureIDs: Set<String>
    ) -> [SharedCapturePayload] {
        let importedIDs = existingCaptureIDs.filter { !$0.isEmpty }
        return captures.filter { !importedIDs.contains($0.id) }
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
        try Self.withExclusiveLock(for: fileURL) {
            var captures = try Self.loadUnlocked(from: fileURL)
            guard !captures.contains(where: { $0.id == payload.id }) else { return }
            captures.append(payload)
            try Self.saveUnlocked(captures, to: fileURL)
        }
    }

    static func pending(from fileURL: URL) throws -> [SharedCapturePayload] {
        try Self.withExclusiveLock(for: fileURL) {
            try Self.loadUnlocked(from: fileURL).filter { [.queued, .syncing, .failed].contains($0.state) }
        }
    }

    static func acknowledge(_ ids: Set<String>, from fileURL: URL) throws {
        guard !ids.isEmpty else { return }
        try Self.withExclusiveLock(for: fileURL) {
            var captures = try Self.loadUnlocked(from: fileURL)
            for index in captures.indices where ids.contains(captures[index].id) {
                captures[index].state = .imported
                captures[index].userReadableError = ""
            }
            try Self.saveUnlocked(captures, to: fileURL)
        }
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

    static func beginAttemptInSharedContainer(_ id: String, at date: Date = .now) throws {
        guard let fileURL = Self.sharedFileURL() else {
            throw SharedCaptureStoreError.sharedContainerUnavailable(
                appGroupIdentifier: Self.appGroupIdentifier)
        }
        try Self.beginAttempt(id, from: fileURL, at: date)
    }

    static func markFailedInSharedContainer(_ id: String, error: String) throws {
        guard let fileURL = Self.sharedFileURL() else {
            throw SharedCaptureStoreError.sharedContainerUnavailable(
                appGroupIdentifier: Self.appGroupIdentifier)
        }
        try Self.markFailed(id, error: error, from: fileURL)
    }

    static func load(from fileURL: URL) throws -> [SharedCapturePayload] {
        try Self.withExclusiveLock(for: fileURL) { try Self.loadUnlocked(from: fileURL) }
    }

    static func envelope(_ id: String, from fileURL: URL) throws -> SharedCapturePayload? {
        try Self.withExclusiveLock(for: fileURL) {
            try Self.loadUnlocked(from: fileURL).first { $0.id == id }
        }
    }

    static func beginAttempt(_ id: String, from fileURL: URL, at date: Date = .now) throws {
        try Self.transition(id, from: fileURL) { capture in
            capture.state = .syncing
            capture.attemptCount += 1
            capture.lastAttemptAt = date
            capture.userReadableError = ""
        }
    }

    static func markFailed(_ id: String, error: String, from fileURL: URL) throws {
        try Self.transition(id, from: fileURL) { capture in
            capture.state = .failed
            capture.userReadableError = error
        }
    }

    static func retry(_ id: String, from fileURL: URL) throws {
        try Self.transition(id, from: fileURL) { capture in
            capture.state = .queued
            capture.userReadableError = ""
        }
    }

    static func markSynced(_ id: String, from fileURL: URL) throws {
        try Self.transition(id, from: fileURL) { capture in
            capture.state = .synced
            capture.userReadableError = ""
        }
    }

    private static func transition(
        _ id: String,
        from fileURL: URL,
        mutation: (inout SharedCapturePayload) -> Void) throws
    {
        try Self.withExclusiveLock(for: fileURL) {
            var captures = try Self.loadUnlocked(from: fileURL)
            guard let index = captures.firstIndex(where: { $0.id == id }) else { return }
            mutation(&captures[index])
            try Self.saveUnlocked(captures, to: fileURL)
        }
    }

    private static func loadUnlocked(from fileURL: URL) throws -> [SharedCapturePayload] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return [] }
        return try JSONDecoder().decode([SharedCapturePayload].self, from: data)
    }

    private static func saveUnlocked(_ captures: [SharedCapturePayload], to fileURL: URL) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(captures)
        try data.write(to: fileURL, options: [.atomic])
    }

    private static func withExclusiveLock<T>(for fileURL: URL, operation: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        #if canImport(Darwin)
        let lockURL = fileURL.appendingPathExtension("lock")
        let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        defer { Darwin.close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw POSIXError(.EIO) }
        defer { flock(descriptor, LOCK_UN) }
        #endif
        return try operation()
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
