import Foundation
import SwiftData

enum AgentRunStatus: String, CaseIterable, Identifiable {
    case prepared
    case handedOff
    case running
    case needsReview
    case completed
    case failed
    case canceled

    var id: String { self.rawValue }
}

@Model
final class AgentRun {
    var id: String = UUID().uuidString
    var taskID: String = ""
    var projectID: String?
    var taskTitleSnapshot: String = ""
    var projectNameSnapshot: String?
    var targetRawValue: String = AgentTarget.codex.rawValue
    var statusRawValue: String = AgentRunStatus.prepared.rawValue
    var promptSnapshot: String = ""
    var repositoryPathSnapshot: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var startedAt: Date?
    var finishedAt: Date?
    var resultSummary: String = ""
    var evidenceURLString: String = ""
    var errorMessage: String = ""

    init(
        id: String = UUID().uuidString,
        taskID: String,
        projectID: String? = nil,
        taskTitleSnapshot: String,
        projectNameSnapshot: String? = nil,
        targetRawValue: String = AgentTarget.codex.rawValue,
        statusRawValue: String = AgentRunStatus.prepared.rawValue,
        promptSnapshot: String = "",
        repositoryPathSnapshot: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        resultSummary: String = "",
        evidenceURLString: String = "",
        errorMessage: String = "")
    {
        self.id = id
        self.taskID = taskID
        self.projectID = projectID
        self.taskTitleSnapshot = taskTitleSnapshot
        self.projectNameSnapshot = projectNameSnapshot
        self.targetRawValue = targetRawValue
        self.statusRawValue = statusRawValue
        self.promptSnapshot = promptSnapshot
        self.repositoryPathSnapshot = repositoryPathSnapshot
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.resultSummary = resultSummary
        self.evidenceURLString = evidenceURLString
        self.errorMessage = errorMessage
    }

    var status: AgentRunStatus {
        get { AgentRunStatus(rawValue: self.statusRawValue) ?? .prepared }
        set { self.statusRawValue = newValue.rawValue }
    }

    var target: AgentTarget? {
        AgentTarget(rawValue: self.targetRawValue)
    }
}
