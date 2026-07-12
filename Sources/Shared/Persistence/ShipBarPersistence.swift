import Foundation
import SwiftData

enum ShipBarPersistence {
    private static let lastErrorKey = "ShipBarPersistence.lastError"

    @MainActor
    @discardableResult
    static func save(_ context: ModelContext, operation: String, notifiesSync: Bool = true) -> Bool {
        do {
            try context.save()
            UserDefaults.standard.removeObject(forKey: Self.lastErrorKey)
            if notifiesSync {
                ShipBarSyncHub.notify(.localMutation)
            }
            return true
        } catch {
            let message = "\(operation): \(error.localizedDescription)"
            UserDefaults.standard.set(message, forKey: Self.lastErrorKey)
            Self.writeDiagnostic(message)
            return false
        }
    }

    static var statusText: String {
        Self.lastError == nil ? "OK" : "Needs attention"
    }

    static var detailText: String {
        Self.lastError ?? "Recent local saves completed without errors."
    }

    private static var lastError: String? {
        UserDefaults.standard.string(forKey: Self.lastErrorKey)
    }

    private static func writeDiagnostic(_ line: String) {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShipBarPersistence.txt")
        let entry = "\(Date()) \(line)\n"
        if let data = entry.data(using: .utf8),
           let handle = try? FileHandle(forWritingTo: url)
        {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? entry.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
