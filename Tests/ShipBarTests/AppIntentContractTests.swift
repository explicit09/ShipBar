import Foundation
import Testing

@Suite("ShipBar deep links")
struct ShipBarDeepLinkTests {
    @Test("destination URLs parse to their destinations")
    func destinationsParse() {
        #expect(ShipBarDeepLink(url: URL(string: "shipbar://inbox")!) == .inbox)
        #expect(ShipBarDeepLink(url: URL(string: "shipbar://today")!) == .today)
        #expect(ShipBarDeepLink(url: URL(string: "shipbar://task/abc-123/prepare")!) == .prepareTask(id: "abc-123"))
    }

    @Test("unknown or malformed URLs are rejected")
    func malformedURLsRejected() {
        #expect(ShipBarDeepLink(url: URL(string: "shipbar://unknown")!) == nil)
        #expect(ShipBarDeepLink(url: URL(string: "https://inbox")!) == nil)
        #expect(ShipBarDeepLink(url: URL(string: "shipbar://task//prepare")!) == nil)
        #expect(ShipBarDeepLink(url: URL(string: "shipbar://task/abc-123/delete")!) == nil)
    }
}

@Suite("App intent source contracts")
struct AppIntentContractTests {
    @Test("capture intent queues text with a dialog containing the capture id")
    func captureIntentContract() throws {
        let source = try self.source("Sources/iOS/Intents/CaptureInShipBarIntent.swift")

        #expect(source.contains("struct CaptureInShipBarIntent: AppIntent"))
        #expect(source.contains("Capture in ShipBar"))
        #expect(source.contains("@Parameter(title: \"Text\")"))
        #expect(source.contains("@Parameter(title: \"Source URL\")"))
        #expect(source.contains("SharedCaptureStore.appendToSharedContainer"))
        #expect(source.contains("Queued for ShipBar"))
        #expect(source.contains("payload.id"))
        #expect(source.contains("isEmpty"))
    }

    @Test("navigation intents open the ShipBar deep links")
    func navigationIntentContract() throws {
        let source = try self.source("Sources/iOS/Intents/OpenShipBarDestinationIntents.swift")

        #expect(source.contains("struct ShowShipBarInboxIntent: AppIntent"))
        #expect(source.contains("struct ShowFlightPlanIntent: AppIntent"))
        #expect(source.contains("struct PrepareTaskForCodexIntent: AppIntent"))
        #expect(source.contains("shipbar://inbox"))
        #expect(source.contains("shipbar://today"))
        #expect(source.contains("shipbar://task/"))
        #expect(source.contains("/prepare"))
    }

    @Test("shortcuts provider registers suggested phrases")
    func shortcutsProviderContract() throws {
        let source = try self.source("Sources/iOS/Intents/ShipBarShortcutsProvider.swift")

        #expect(source.contains("AppShortcutsProvider"))
        #expect(source.contains("CaptureInShipBarIntent"))
        #expect(source.contains("ShowShipBarInboxIntent"))
        #expect(source.contains("ShowFlightPlanIntent"))
        #expect(source.contains(".applicationName"))
    }

    @Test("iOS root handles the shipbar URL scheme")
    func rootHandlesURLScheme() throws {
        let rootSource = try self.source("Sources/Shared/Views/ShipBarRootView.swift")
        let projectSource = try self.source("project.yml")

        #expect(rootSource.contains(".onOpenURL"))
        #expect(rootSource.contains("ShipBarDeepLink"))
        #expect(projectSource.contains("CFBundleURLSchemes"))
        #expect(projectSource.contains("shipbar"))
    }

    private func source(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
