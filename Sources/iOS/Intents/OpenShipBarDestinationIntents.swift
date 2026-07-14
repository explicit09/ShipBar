import AppIntents
import Foundation
import UIKit

struct ShowShipBarInboxIntent: AppIntent {
    static let title: LocalizedStringResource = "Show ShipBar Inbox"
    static let description = IntentDescription("Open the ShipBar Inbox for triage.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        await UIApplication.shared.open(URL(string: "shipbar://inbox")!)
        return .result()
    }
}

struct ShowFlightPlanIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Today's Flight Plan"
    static let description = IntentDescription("Open today's focus list in ShipBar.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        await UIApplication.shared.open(URL(string: "shipbar://today")!)
        return .result()
    }
}

struct PrepareTaskForCodexIntent: AppIntent {
    static let title: LocalizedStringResource = "Prepare Task for Codex"
    static let description = IntentDescription("Open a ShipBar task ready to hand off to Codex.")
    static let openAppWhenRun = true

    @Parameter(title: "Task ID") var taskID: String

    @MainActor
    func perform() async throws -> some IntentResult {
        let trimmed = self.taskID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw self.$taskID.needsValueError("Which task should be prepared?")
        }
        guard let url = URL(string: "shipbar://task/\(trimmed)/prepare") else {
            throw self.$taskID.needsValueError("That task ID cannot form a ShipBar link.")
        }
        await UIApplication.shared.open(url)
        return .result()
    }
}
