import Foundation

struct ShipBarCLIUsageError: LocalizedError, Equatable {
    let message: String

    var errorDescription: String? { self.message }
}

enum ShipBarCLICore {
    static let defaultTimeout: TimeInterval = 15

    enum ExitCode: Int32 {
        case success = 0
        case usage = 1
        case commandFailed = 2
        case timeout = 3
        case bridgeUnavailable = 4
    }

    struct Invocation: Equatable {
        let command: ShipBarBridgeCommand
        let timeout: TimeInterval
    }

    static let usage = """
    usage: shipbarctl <command> [options]

    commands:
      list-prepared
      get-context     --run <id>
      claim           --run <id>
      mark-running    --run <id>
      request-review  --run <id> --summary <text> --evidence <path> [--evidence <path> ...]
      mark-failed     --run <id> --message <text>
      cancel          --run <id> --message <text>
      search-tasks    --query <text>
      get-today
      get-task        --task <id>
      run-status      --run <id>
      queue-capture   --capture <id> --title <text> [--description <text>] [--project <name>] [--priority <value>] [--due-at <iso-date>]
      prepare-run     --task <id> --repository <path> [--instructions <text>]

    options:
      --timeout <seconds>   response wait (default \(Int(Self.defaultTimeout)))
    """

    static func parse(_ arguments: [String]) throws -> Invocation {
        var remaining = arguments[...]
        guard let commandName = remaining.popFirst() else {
            throw ShipBarCLIUsageError(message: "Missing command.\n\(Self.usage)")
        }

        var options: [String: [String]] = [:]
        while let flag = remaining.popFirst() {
            guard flag.hasPrefix("--") else {
                throw ShipBarCLIUsageError(message: "Unexpected argument '\(flag)'.")
            }
            guard let value = remaining.popFirst() else {
                throw ShipBarCLIUsageError(message: "Flag '\(flag)' needs a value.")
            }
            options[String(flag.dropFirst(2)), default: []].append(value)
        }

        let timeout: TimeInterval
        if let raw = options["timeout"]?.last {
            guard let parsed = TimeInterval(raw), parsed > 0 else {
                throw ShipBarCLIUsageError(message: "Invalid --timeout '\(raw)'.")
            }
            timeout = parsed
        } else {
            timeout = Self.defaultTimeout
        }

        func required(_ name: String) throws -> String {
            guard let value = options[name]?.last, !value.isEmpty else {
                throw ShipBarCLIUsageError(message: "Command '\(commandName)' requires --\(name).")
            }
            return value
        }

        let command: ShipBarBridgeCommand
        switch commandName {
        case "list-prepared":
            command = .listPrepared
        case "get-context":
            command = try .getContext(runID: required("run"))
        case "claim":
            command = try .claim(runID: required("run"))
        case "mark-running":
            command = try .markRunning(runID: required("run"))
        case "request-review":
            let evidence = options["evidence"] ?? []
            command = try .requestReview(
                runID: required("run"),
                summary: required("summary"),
                evidencePaths: evidence)
        case "mark-failed":
            command = try .markFailed(runID: required("run"), message: required("message"))
        case "cancel":
            command = try .cancel(runID: required("run"), message: required("message"))
        case "search-tasks":
            command = try .searchTasks(query: required("query"))
        case "get-today":
            command = .getToday
        case "get-task":
            command = try .getTask(taskID: required("task"))
        case "run-status":
            command = try .getRunStatus(runID: required("run"))
        case "queue-capture":
            command = try .queueCapture(
                captureID: required("capture"),
                title: required("title"),
                description: options["description"]?.last ?? "",
                projectName: options["project"]?.last,
                priority: options["priority"]?.last ?? "normal",
                dueAt: options["due-at"]?.last)
        case "prepare-run":
            command = try .prepareRun(
                taskID: required("task"),
                repositoryPath: required("repository"),
                instructions: options["instructions"]?.last ?? "")
        default:
            throw ShipBarCLIUsageError(message: "Unknown command '\(commandName)'.\n\(Self.usage)")
        }

        return Invocation(command: command, timeout: timeout)
    }
}
