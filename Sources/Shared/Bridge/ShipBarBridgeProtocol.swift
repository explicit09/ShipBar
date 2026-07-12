import Foundation

enum ShipBarBridgeSchema {
    static let version = 1
}

enum ShipBarBridgeError: LocalizedError, Equatable {
    case unsupportedSchemaVersion(Int)
    case unknownCommand(String)
    case bridgeNotReady

    var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            "Unsupported ShipBar bridge schema version \(version); this build speaks version \(ShipBarBridgeSchema.version)."
        case .unknownCommand(let type):
            "Unknown ShipBar bridge command '\(type)'. Only the closed command set is accepted."
        case .bridgeNotReady:
            "ShipBar has not set up its bridge yet. Open the ShipBar menu app once, then try again."
        }
    }
}

enum ShipBarBridgeCommand: Equatable, Sendable {
    case listPrepared
    case getContext(runID: String)
    case claim(runID: String)
    case markRunning(runID: String)
    case requestReview(runID: String, summary: String, evidencePaths: [String])
    case markFailed(runID: String, message: String)
    case cancel(runID: String, message: String)
    case searchTasks(query: String)
    case getToday
    case getTask(taskID: String)
    case getRunStatus(runID: String)

    var runID: String? {
        switch self {
        case .listPrepared, .searchTasks, .getToday, .getTask: nil
        case .getContext(let runID),
             .claim(let runID),
             .markRunning(let runID),
             .requestReview(let runID, _, _),
             .markFailed(let runID, _),
             .cancel(let runID, _),
             .getRunStatus(let runID):
            runID
        }
    }
}

extension ShipBarBridgeCommand: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, runID, summary, evidencePaths, message, query, taskID
    }

    private var typeName: String {
        switch self {
        case .listPrepared: "listPrepared"
        case .getContext: "getContext"
        case .claim: "claim"
        case .markRunning: "markRunning"
        case .requestReview: "requestReview"
        case .markFailed: "markFailed"
        case .cancel: "cancel"
        case .searchTasks: "searchTasks"
        case .getToday: "getToday"
        case .getTask: "getTask"
        case .getRunStatus: "getRunStatus"
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.typeName, forKey: .type)
        switch self {
        case .listPrepared, .getToday:
            break
        case .getContext(let runID), .claim(let runID), .markRunning(let runID), .getRunStatus(let runID):
            try container.encode(runID, forKey: .runID)
        case let .requestReview(runID, summary, evidencePaths):
            try container.encode(runID, forKey: .runID)
            try container.encode(summary, forKey: .summary)
            try container.encode(evidencePaths, forKey: .evidencePaths)
        case let .markFailed(runID, message), let .cancel(runID, message):
            try container.encode(runID, forKey: .runID)
            try container.encode(message, forKey: .message)
        case .searchTasks(let query):
            try container.encode(query, forKey: .query)
        case .getTask(let taskID):
            try container.encode(taskID, forKey: .taskID)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "listPrepared":
            self = .listPrepared
        case "getContext":
            self = try .getContext(runID: container.decode(String.self, forKey: .runID))
        case "claim":
            self = try .claim(runID: container.decode(String.self, forKey: .runID))
        case "markRunning":
            self = try .markRunning(runID: container.decode(String.self, forKey: .runID))
        case "requestReview":
            self = try .requestReview(
                runID: container.decode(String.self, forKey: .runID),
                summary: container.decode(String.self, forKey: .summary),
                evidencePaths: container.decode([String].self, forKey: .evidencePaths))
        case "markFailed":
            self = try .markFailed(
                runID: container.decode(String.self, forKey: .runID),
                message: container.decode(String.self, forKey: .message))
        case "cancel":
            self = try .cancel(
                runID: container.decode(String.self, forKey: .runID),
                message: container.decode(String.self, forKey: .message))
        case "searchTasks":
            self = try .searchTasks(query: container.decode(String.self, forKey: .query))
        case "getToday":
            self = .getToday
        case "getTask":
            self = try .getTask(taskID: container.decode(String.self, forKey: .taskID))
        case "getRunStatus":
            self = try .getRunStatus(runID: container.decode(String.self, forKey: .runID))
        default:
            throw ShipBarBridgeError.unknownCommand(type)
        }
    }
}

struct ShipBarBridgeRequest: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let schemaVersion: Int
    let createdAt: Date
    let command: ShipBarBridgeCommand

    init(
        id: String = UUID().uuidString,
        createdAt: Date = .now,
        command: ShipBarBridgeCommand)
    {
        self.id = id
        self.schemaVersion = ShipBarBridgeSchema.version
        self.createdAt = createdAt
        self.command = command
    }

    private enum CodingKeys: String, CodingKey {
        case id, schemaVersion, createdAt, command
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == ShipBarBridgeSchema.version else {
            throw ShipBarBridgeError.unsupportedSchemaVersion(schemaVersion)
        }
        self.id = try container.decode(String.self, forKey: .id)
        self.schemaVersion = schemaVersion
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.command = try container.decode(ShipBarBridgeCommand.self, forKey: .command)
    }
}

struct ShipBarBridgeRunSummary: Codable, Equatable, Sendable {
    let runID: String
    let taskID: String
    let taskTitle: String
    let projectName: String?
    let repositoryPath: String
    let status: String
    let updatedAt: Date
}

struct ShipBarBridgeRunContext: Codable, Equatable, Sendable {
    let run: ShipBarBridgeRunSummary
    let prompt: String
    let taskDescription: String
    let target: String
}

struct ShipBarBridgeTaskSummary: Codable, Equatable, Sendable {
    let taskID: String
    let title: String
    let taskDescription: String
    let status: String
    let priority: String
    let type: String
    let projectName: String?
    let dueDate: Date?
    let focusDate: Date?
    let focusOrder: Int?
    let isInbox: Bool
    let updatedAt: Date
}

enum ShipBarBridgeResult: Codable, Equatable, Sendable {
    case acknowledged
    case preparedRuns([ShipBarBridgeRunSummary])
    case runContext(ShipBarBridgeRunContext)
    case runStatus(ShipBarBridgeRunSummary)
    case tasks([ShipBarBridgeTaskSummary])

    private enum CodingKeys: String, CodingKey {
        case type, runs, context, run, tasks
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .acknowledged:
            try container.encode("acknowledged", forKey: .type)
        case .preparedRuns(let runs):
            try container.encode("preparedRuns", forKey: .type)
            try container.encode(runs, forKey: .runs)
        case .runContext(let context):
            try container.encode("runContext", forKey: .type)
            try container.encode(context, forKey: .context)
        case .runStatus(let run):
            try container.encode("runStatus", forKey: .type)
            try container.encode(run, forKey: .run)
        case .tasks(let tasks):
            try container.encode("tasks", forKey: .type)
            try container.encode(tasks, forKey: .tasks)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "acknowledged":
            self = .acknowledged
        case "preparedRuns":
            self = try .preparedRuns(container.decode([ShipBarBridgeRunSummary].self, forKey: .runs))
        case "runContext":
            self = try .runContext(container.decode(ShipBarBridgeRunContext.self, forKey: .context))
        case "runStatus":
            self = try .runStatus(container.decode(ShipBarBridgeRunSummary.self, forKey: .run))
        case "tasks":
            self = try .tasks(container.decode([ShipBarBridgeTaskSummary].self, forKey: .tasks))
        default:
            throw ShipBarBridgeError.unknownCommand(type)
        }
    }
}

struct ShipBarBridgeResponse: Codable, Equatable, Sendable {
    let requestID: String
    let schemaVersion: Int
    let createdAt: Date
    let result: ShipBarBridgeResult?
    let errorMessage: String?

    var isSuccess: Bool { self.errorMessage == nil }

    private init(
        requestID: String,
        createdAt: Date,
        result: ShipBarBridgeResult?,
        errorMessage: String?)
    {
        self.requestID = requestID
        self.schemaVersion = ShipBarBridgeSchema.version
        self.createdAt = createdAt
        self.result = result
        self.errorMessage = errorMessage
    }

    static func success(
        requestID: String,
        result: ShipBarBridgeResult,
        createdAt: Date = .now) -> ShipBarBridgeResponse
    {
        ShipBarBridgeResponse(requestID: requestID, createdAt: createdAt, result: result, errorMessage: nil)
    }

    static func failure(
        requestID: String,
        message: String,
        createdAt: Date = .now) -> ShipBarBridgeResponse
    {
        ShipBarBridgeResponse(requestID: requestID, createdAt: createdAt, result: nil, errorMessage: message)
    }

    private enum CodingKeys: String, CodingKey {
        case requestID, schemaVersion, createdAt, result, errorMessage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == ShipBarBridgeSchema.version else {
            throw ShipBarBridgeError.unsupportedSchemaVersion(schemaVersion)
        }
        self.requestID = try container.decode(String.self, forKey: .requestID)
        self.schemaVersion = schemaVersion
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.result = try container.decodeIfPresent(ShipBarBridgeResult.self, forKey: .result)
        self.errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
    }
}
