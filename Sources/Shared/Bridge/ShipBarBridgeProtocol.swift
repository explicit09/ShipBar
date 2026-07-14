import Foundation

enum ShipBarBridgeSchema {
    static let version = 2
}

enum ShipBarProductivityCommandKind: String, Codable, Equatable, Sendable {
    case createTask, updateTask, trashTask, restoreTask, permanentlyDeleteTask
    case createProject, updateProject, trashProject, restoreProject, permanentlyDeleteProject
}

struct ShipBarTaskPatch: Codable, Equatable, Sendable {
    var title: String?
    var description: String?
    var prompt: String?
    var status: String?
    var priority: String?
    var type: String?
    var projectID: String?
    var projectName: String?
    var dueAt: String?
    var focusDate: String?
    var focusOrder: Int?
    var sourceApp: String?
    var sourceURL: String?
    var clearProject: Bool?
    var clearDueDate: Bool?
    var removeFromToday: Bool?

    init(
        title: String? = nil, description: String? = nil, prompt: String? = nil,
        status: String? = nil, priority: String? = nil, type: String? = nil,
        projectID: String? = nil, projectName: String? = nil, dueAt: String? = nil,
        focusDate: String? = nil, focusOrder: Int? = nil, sourceApp: String? = nil,
        sourceURL: String? = nil, clearProject: Bool? = nil,
        clearDueDate: Bool? = nil, removeFromToday: Bool? = nil)
    {
        self.title = title; self.description = description; self.prompt = prompt
        self.status = status; self.priority = priority; self.type = type
        self.projectID = projectID; self.projectName = projectName; self.dueAt = dueAt
        self.focusDate = focusDate; self.focusOrder = focusOrder; self.sourceApp = sourceApp
        self.sourceURL = sourceURL; self.clearProject = clearProject
        self.clearDueDate = clearDueDate; self.removeFromToday = removeFromToday
    }
}

struct ShipBarProjectPatch: Codable, Equatable, Sendable {
    var name: String?
    var outcome: String?
    var basePrompt: String?
    var repoPath: String?
    var color: String?
    var icon: String?
    var sortOrder: Int?

    init(
        name: String? = nil, outcome: String? = nil, basePrompt: String? = nil,
        repoPath: String? = nil, color: String? = nil, icon: String? = nil,
        sortOrder: Int? = nil)
    {
        self.name = name; self.outcome = outcome; self.basePrompt = basePrompt
        self.repoPath = repoPath; self.color = color; self.icon = icon
        self.sortOrder = sortOrder
    }
}

struct ShipBarProductivityCommand: Codable, Equatable, Sendable {
    let kind: ShipBarProductivityCommandKind
    var recordID: String?
    var expectedRevision: Int?
    var task: ShipBarTaskPatch?
    var project: ShipBarProjectPatch?
    var taskHandling: String?

    init(
        kind: ShipBarProductivityCommandKind, recordID: String? = nil,
        expectedRevision: Int? = nil, task: ShipBarTaskPatch? = nil,
        project: ShipBarProjectPatch? = nil, taskHandling: String? = nil)
    {
        self.kind = kind; self.recordID = recordID; self.expectedRevision = expectedRevision
        self.task = task; self.project = project; self.taskHandling = taskHandling
    }
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
    case resetAllData(confirmation: String)
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
    case getProductivitySnapshot
    case getRunStatus(runID: String)
    case queueCapture(
        captureID: String,
        title: String,
        description: String,
        projectName: String?,
        priority: String,
        dueAt: String?)
    case prepareRun(taskID: String, repositoryPath: String, instructions: String, preparationKey: String? = nil)
    case applyProductivity(commandID: String, command: ShipBarProductivityCommand)

    var runID: String? {
        switch self {
        case .resetAllData, .listPrepared, .searchTasks, .getToday, .getTask, .getProductivitySnapshot, .queueCapture, .prepareRun, .applyProductivity: nil
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
        case type, confirmation, runID, summary, evidencePaths, message, query, taskID
        case captureID, title, description, projectName, priority, dueAt
        case repositoryPath, instructions, preparationKey, commandID, productivityCommand
    }

    private var typeName: String {
        switch self {
        case .resetAllData: "resetAllData"
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
        case .getProductivitySnapshot: "getProductivitySnapshot"
        case .getRunStatus: "getRunStatus"
        case .queueCapture: "queueCapture"
        case .prepareRun: "prepareRun"
        case .applyProductivity: "applyProductivity"
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.typeName, forKey: .type)
        switch self {
        case .resetAllData(let confirmation):
            try container.encode(confirmation, forKey: .confirmation)
        case .listPrepared, .getToday, .getProductivitySnapshot:
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
        case let .queueCapture(captureID, title, description, projectName, priority, dueAt):
            try container.encode(captureID, forKey: .captureID)
            try container.encode(title, forKey: .title)
            try container.encode(description, forKey: .description)
            try container.encodeIfPresent(projectName, forKey: .projectName)
            try container.encode(priority, forKey: .priority)
            try container.encodeIfPresent(dueAt, forKey: .dueAt)
        case let .prepareRun(taskID, repositoryPath, instructions, preparationKey):
            try container.encode(taskID, forKey: .taskID)
            try container.encode(repositoryPath, forKey: .repositoryPath)
            try container.encode(instructions, forKey: .instructions)
            try container.encodeIfPresent(preparationKey, forKey: .preparationKey)
        case let .applyProductivity(commandID, command):
            try container.encode(commandID, forKey: .commandID)
            try container.encode(command, forKey: .productivityCommand)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "resetAllData":
            self = try .resetAllData(confirmation: container.decode(String.self, forKey: .confirmation))
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
        case "getProductivitySnapshot":
            self = .getProductivitySnapshot
        case "getRunStatus":
            self = try .getRunStatus(runID: container.decode(String.self, forKey: .runID))
        case "queueCapture":
            self = try .queueCapture(
                captureID: container.decode(String.self, forKey: .captureID),
                title: container.decode(String.self, forKey: .title),
                description: container.decodeIfPresent(String.self, forKey: .description) ?? "",
                projectName: container.decodeIfPresent(String.self, forKey: .projectName),
                priority: container.decodeIfPresent(String.self, forKey: .priority) ?? "normal",
                dueAt: container.decodeIfPresent(String.self, forKey: .dueAt))
        case "prepareRun":
            self = try .prepareRun(
                taskID: container.decode(String.self, forKey: .taskID),
                repositoryPath: container.decode(String.self, forKey: .repositoryPath),
                instructions: container.decodeIfPresent(String.self, forKey: .instructions) ?? "",
                preparationKey: container.decodeIfPresent(String.self, forKey: .preparationKey))
        case "applyProductivity":
            self = try .applyProductivity(
                commandID: container.decode(String.self, forKey: .commandID),
                command: container.decode(ShipBarProductivityCommand.self, forKey: .productivityCommand))
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
    let prompt: String
    let status: String
    let priority: String
    let type: String
    let projectName: String?
    let dueDate: Date?
    let focusDate: Date?
    let focusOrder: Int?
    let isInbox: Bool
    let updatedAt: Date
    let revision: Int
    let trashedAt: Date?
    let sourceApp: String
    let sourceURL: String
}

struct ShipBarBridgeProjectSummary: Codable, Equatable, Sendable {
    let projectID: String
    let name: String
    let outcome: String
    let basePrompt: String
    let repoPath: String
    let color: String
    let icon: String
    let sortOrder: Int
    let updatedAt: Date
    let revision: Int
    let trashedAt: Date?
}

struct ShipBarBridgeCommandResult: Codable, Equatable, Sendable {
    let commandID: String
    let status: String
    let summary: String
    let task: ShipBarBridgeTaskSummary?
    let project: ShipBarBridgeProjectSummary?
    let deletedRecordID: String?
    let deletedRecordType: String?
}

struct ShipBarBridgeProductivitySnapshot: Codable, Equatable, Sendable {
    let tasks: [ShipBarBridgeTaskSummary]
    let projects: [ShipBarBridgeProjectSummary]
}

enum ShipBarBridgeResult: Codable, Equatable, Sendable {
    case acknowledged
    case preparedRuns([ShipBarBridgeRunSummary])
    case runContext(ShipBarBridgeRunContext)
    case runStatus(ShipBarBridgeRunSummary)
    case tasks([ShipBarBridgeTaskSummary])
    case productivitySnapshot(ShipBarBridgeProductivitySnapshot)
    case commandResult(ShipBarBridgeCommandResult)

    private enum CodingKeys: String, CodingKey {
        case type, runs, context, run, tasks, projects, commandResult
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
        case .productivitySnapshot(let snapshot):
            try container.encode("productivitySnapshot", forKey: .type)
            try container.encode(snapshot.tasks, forKey: .tasks)
            try container.encode(snapshot.projects, forKey: .projects)
        case .commandResult(let result):
            try container.encode("commandResult", forKey: .type)
            try container.encode(result, forKey: .commandResult)
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
        case "productivitySnapshot":
            self = try .productivitySnapshot(ShipBarBridgeProductivitySnapshot(
                tasks: container.decode([ShipBarBridgeTaskSummary].self, forKey: .tasks),
                projects: container.decode([ShipBarBridgeProjectSummary].self, forKey: .projects)))
        case "commandResult":
            self = try .commandResult(container.decode(ShipBarBridgeCommandResult.self, forKey: .commandResult))
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
