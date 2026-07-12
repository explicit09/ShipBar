import Foundation

/// shipbarctl — the signed local helper that exchanges closed bridge
/// commands with the running ShipBar menu app through the App Group.
/// Responses stream to stdout as raw JSON; diagnostics go to stderr.
@main
enum ShipBarCLI {
    static func main() async {
        let invocation: ShipBarCLICore.Invocation
        do {
            invocation = try ShipBarCLICore.parse(Array(CommandLine.arguments.dropFirst()))
        } catch {
            Self.printError(error.localizedDescription)
            exit(ShipBarCLICore.ExitCode.usage.rawValue)
        }

        let store: ShipBarBridgeStore
        do {
            // Never create the App Group container from here: the
            // sandboxed app must be its creator, or the app's reads of
            // it hang forever.
            store = try ShipBarBridgeStore.appGroup(requireExistingContainer: true)
        } catch {
            Self.printError(error.localizedDescription)
            exit(ShipBarCLICore.ExitCode.bridgeUnavailable.rawValue)
        }

        let request = ShipBarBridgeRequest(command: invocation.command)
        do {
            try store.append(request)
        } catch {
            Self.printError("Could not queue the bridge request: \(error.localizedDescription)")
            exit(ShipBarCLICore.ExitCode.bridgeUnavailable.rawValue)
        }

        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("com.tadies.ShipBar.bridge.request"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true)

        let response: ShipBarBridgeResponse?
        do {
            response = try await store.waitForResponse(
                requestID: request.id,
                timeout: invocation.timeout)
        } catch {
            Self.printError("Failed while waiting for ShipBar: \(error.localizedDescription)")
            exit(ShipBarCLICore.ExitCode.bridgeUnavailable.rawValue)
        }

        guard let response else {
            try? store.removeRequest(id: request.id)
            Self.printError("Timed out after \(Int(invocation.timeout))s. Is the ShipBar menu app running?")
            exit(ShipBarCLICore.ExitCode.timeout.rawValue)
        }

        try? store.removeResponse(requestID: request.id)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            var data = try encoder.encode(response)
            data.append(Data("\n".utf8))
            FileHandle.standardOutput.write(data)
        } catch {
            Self.printError("Could not encode the bridge response: \(error.localizedDescription)")
            exit(ShipBarCLICore.ExitCode.bridgeUnavailable.rawValue)
        }

        exit(response.isSuccess
            ? ShipBarCLICore.ExitCode.success.rawValue
            : ShipBarCLICore.ExitCode.commandFailed.rawValue)
    }

    private static func printError(_ message: String) {
        FileHandle.standardError.write(Data("shipbarctl: \(message)\n".utf8))
    }
}
