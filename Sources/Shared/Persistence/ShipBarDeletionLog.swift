import Foundation
import SwiftData

enum ShipBarDeletionKind: String, Codable, CaseIterable {
    case project
    case task
    case run
}

@Model
final class ShipBarDeletionTombstone {
    var id: String = UUID().uuidString
    var recordKind: String = ""
    var recordID: String = ""
    var taskHandling: String?
    var deletedAt: Date = Date()

    init(
        id: String = UUID().uuidString,
        recordKind: String,
        recordID: String,
        taskHandling: String? = nil,
        deletedAt: Date = .now)
    {
        self.id = id
        self.recordKind = recordKind
        self.recordID = recordID
        self.taskHandling = taskHandling
        self.deletedAt = deletedAt
    }

    var cloudRecordName: String {
        Self.cloudRecordName(kind: self.recordKind, id: self.recordID)
    }

    static func cloudRecordName(kind: String, id: String) -> String {
        "\(kind):\(id)"
    }
}

enum ShipBarDeletionLog {
    @MainActor
    static func record(
        _ kind: ShipBarDeletionKind,
        id: String,
        taskHandling: String? = nil,
        deletedAt: Date = .now,
        in context: ModelContext)
    {
        let recordID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !recordID.isEmpty else { return }

        let existing = Self.tombstone(kind: kind, id: recordID, in: context)
        if let existing {
            existing.deletedAt = max(existing.deletedAt, deletedAt)
            if let taskHandling {
                existing.taskHandling = taskHandling
            }
            return
        }

        context.insert(ShipBarDeletionTombstone(
            recordKind: kind.rawValue,
            recordID: recordID,
            taskHandling: taskHandling,
            deletedAt: deletedAt))
    }

    @MainActor
    static func isDeleted(_ kind: ShipBarDeletionKind, id: String, in context: ModelContext) -> Bool {
        Self.tombstone(kind: kind, id: id, in: context) != nil
    }

    @MainActor
    static func tombstones(in context: ModelContext) -> [ShipBarDeletionTombstone] {
        (try? context.fetch(FetchDescriptor<ShipBarDeletionTombstone>())) ?? []
    }

    @MainActor
    private static func tombstone(
        kind: ShipBarDeletionKind,
        id: String,
        in context: ModelContext) -> ShipBarDeletionTombstone?
    {
        Self.tombstones(in: context).first {
            $0.recordKind == kind.rawValue && $0.recordID == id
        }
    }
}
