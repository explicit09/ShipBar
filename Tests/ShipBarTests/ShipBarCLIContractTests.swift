import Foundation
import Testing

@Suite("shipbarctl argument parsing")
struct ShipBarCLIParsingTests {
    @Test("every closed command parses to its bridge command")
    func commandsParse() throws {
        #expect(try ShipBarCLICore.parse(["list-prepared"]).command == .listPrepared)
        #expect(try ShipBarCLICore.parse(["get-context", "--run", "r1"]).command == .getContext(runID: "r1"))
        #expect(try ShipBarCLICore.parse(["claim", "--run", "r1"]).command == .claim(runID: "r1"))
        #expect(try ShipBarCLICore.parse(["mark-running", "--run", "r1"]).command == .markRunning(runID: "r1"))
        #expect(try ShipBarCLICore.parse([
            "request-review", "--run", "r1", "--summary", "done", "--evidence", "/tmp/a", "--evidence", "/tmp/b",
        ]).command == .requestReview(runID: "r1", summary: "done", evidencePaths: ["/tmp/a", "/tmp/b"]))
        #expect(try ShipBarCLICore.parse([
            "mark-failed", "--run", "r1", "--message", "broke",
        ]).command == .markFailed(runID: "r1", message: "broke"))
        #expect(try ShipBarCLICore.parse([
            "cancel", "--run", "r1", "--message", "stop",
        ]).command == .cancel(runID: "r1", message: "stop"))
        #expect(try ShipBarCLICore.parse(["search-tasks", "--query", "login"]).command == .searchTasks(query: "login"))
        #expect(try ShipBarCLICore.parse(["get-today"]).command == .getToday)
        #expect(try ShipBarCLICore.parse(["get-task", "--task", "t1"]).command == .getTask(taskID: "t1"))
        #expect(try ShipBarCLICore.parse(["run-status", "--run", "r1"]).command == .getRunStatus(runID: "r1"))
        #expect(try ShipBarCLICore.parse([
            "queue-capture", "--capture", "cloud-1", "--title", "Write report",
            "--description", "Detailed notes", "--project", "LEARN-X", "--priority", "high",
        ]).command == .queueCapture(
            captureID: "cloud-1",
            title: "Write report",
            description: "Detailed notes",
            projectName: "LEARN-X",
            priority: "high",
            dueAt: nil))
        #expect(try ShipBarCLICore.parse([
            "prepare-run", "--task", "t1", "--repository", "/tmp/repo", "--instructions", "Run tests",
        ]).command == .prepareRun(taskID: "t1", repositoryPath: "/tmp/repo", instructions: "Run tests"))
        #expect(try ShipBarCLICore.parse([
            "prepare-run", "--task", "t1", "--repository", "/tmp/repo", "--preparation-key", "execution-1",
        ]).command == .prepareRun(
            taskID: "t1", repositoryPath: "/tmp/repo", instructions: "", preparationKey: "execution-1"))

        let commandJSON = #"{"kind":"createTask","task":{"title":"Detailed task","description":"Context","prompt":"Agent steps","priority":"high","type":"feature"}}"#
        #expect(try ShipBarCLICore.parse([
            "apply-command", "--command-id", "command-1", "--command", commandJSON,
        ]).command == .applyProductivity(
            commandID: "command-1",
            command: ShipBarProductivityCommand(
                kind: .createTask,
                task: ShipBarTaskPatch(
                    title: "Detailed task",
                    description: "Context",
                    prompt: "Agent steps",
                    priority: "high",
                    type: "feature"))))
    }

    @Test("timeout flag parses and defaults")
    func timeoutParses() throws {
        #expect(try ShipBarCLICore.parse(["list-prepared"]).timeout == 15)
        #expect(try ShipBarCLICore.parse(["list-prepared", "--timeout", "3"]).timeout == 3)
    }

    @Test("unknown commands and missing arguments are usage errors")
    func usageErrors() {
        #expect(throws: ShipBarCLIUsageError.self) { try ShipBarCLICore.parse([]) }
        #expect(throws: ShipBarCLIUsageError.self) { try ShipBarCLICore.parse(["run-shell", "--script", "x"]) }
        #expect(throws: ShipBarCLIUsageError.self) { try ShipBarCLICore.parse(["claim"]) }
        #expect(throws: ShipBarCLIUsageError.self) { try ShipBarCLICore.parse(["mark-failed", "--run", "r1"]) }
        #expect(throws: ShipBarCLIUsageError.self) { try ShipBarCLICore.parse(["queue-capture", "--capture", "c1"]) }
        #expect(throws: ShipBarCLIUsageError.self) { try ShipBarCLICore.parse(["prepare-run"]) }
        #expect(throws: ShipBarCLIUsageError.self) { try ShipBarCLICore.parse(["apply-command"]) }
        #expect(throws: ShipBarCLIUsageError.self) {
            try ShipBarCLICore.parse(["apply-command", "--command-id", "c1", "--command", "not-json"])
        }
        #expect(throws: ShipBarCLIUsageError.self) { try ShipBarCLICore.parse(["list-prepared", "--timeout", "soon"]) }
    }

    @Test("exit codes are stable for scripting")
    func exitCodes() {
        #expect(ShipBarCLICore.ExitCode.success.rawValue == 0)
        #expect(ShipBarCLICore.ExitCode.usage.rawValue == 1)
        #expect(ShipBarCLICore.ExitCode.commandFailed.rawValue == 2)
        #expect(ShipBarCLICore.ExitCode.timeout.rawValue == 3)
        #expect(ShipBarCLICore.ExitCode.bridgeUnavailable.rawValue == 4)
    }
}

@Suite("shipbarctl source contracts")
struct ShipBarCLIContractTests {
    @Test("responses stream to stdout as JSON and errors to stderr")
    func outputContract() throws {
        let source = try self.source("Sources/CLI/ShipBarCLI.swift")

        #expect(source.contains("FileHandle.standardOutput"))
        #expect(source.contains("FileHandle.standardError"))
        #expect(source.contains("DistributedNotificationCenter"))
        #expect(source.contains("waitForResponse"))
        #expect(source.contains("exit("))
    }

    @Test("the helper refuses to create the app bridge directory")
    func helperNeverCreatesContainer() throws {
        // If the unsandboxed helper creates the container first,
        // containermanagerd never provisions it for the sandboxed app,
        // whose directory reads then hang forever and strand the bridge.
        let source = try self.source("Sources/CLI/ShipBarCLI.swift")

        #expect(source.contains("macApplicationSupport(requireExistingContainer: true)"))
    }

    @Test("the helper never logs prompt bodies")
    func noPromptLogging() throws {
        let entry = try self.source("Sources/CLI/ShipBarCLI.swift")
        let core = try self.source("Sources/CLI/ShipBarCLICore.swift")

        #expect(!entry.contains("prompt"))
        #expect(!core.contains("prompt"))
    }

    @Test("the helper is embedded and entitled for the App Group")
    func embeddingContract() throws {
        let project = try self.source("project.yml")

        #expect(project.contains("ShipBarCLI"))
        #expect(project.contains("PRODUCT_NAME: shipbarctl"))
        #expect(project.contains("Contents/Helpers"))
        #expect(project.contains("Config/CLI/ShipBarCLI.entitlements"))
    }

    private func source(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
