import Foundation
import Testing

@Suite("Final review source contracts")
struct FinalReviewContractTests {
    @Test("Mac project workspace exposes explicit return navigation")
    func macProjectWorkspaceExposesReturnNavigation() throws {
        let workspace = try self.source("Sources/Shared/Views/ProjectWorkspaceView.swift")
        let root = try self.source("Sources/Shared/Views/ShipBarRootView.swift")

        #expect(workspace.contains("let backToProjects: () -> Void"))
        #expect(workspace.contains("#if os(macOS)\n            Button(\"Back to Projects\", systemImage: \"chevron.left\""))
        #expect(root.contains("backToProjects: { self.selectedProjectID = nil }"))
    }

    @Test("destination dock exposes selected state without inventing optional counts")
    func destinationDockAccessibilityIsTruthful() throws {
        let dock = try self.source("Sources/Shared/Views/ShipBarDestinationDock.swift")

        #expect(dock.contains("let actionableCount = self.count(destination)"))
        #expect(dock.contains("if let actionableCount, actionableCount > 0"))
        #expect(dock.contains(".accessibilityRemoveTraits(.isSelected)"))
        #expect(dock.contains(".accessibilityAddTraits(self.selection == destination ? .isSelected : [])"))
        #expect(dock.contains("self.accessibilityLabel(for: destination, actionableCount: actionableCount)"))
    }

    @Test("shared Settings actions have full-width 44 point targets")
    func sharedSettingsActionsHaveAccessibleTargets() throws {
        let root = try self.source("Sources/Shared/Views/ShipBarRootView.swift")
        let actionStart = try #require(root.range(of: "private func settingsActionRow("))
        let actionEnd = try #require(root.range(of: "@ViewBuilder", range: actionStart.upperBound..<root.endIndex))
        let action = String(root[actionStart.lowerBound..<actionEnd.lowerBound])

        #expect(action.contains(".frame(maxWidth: .infinity, minHeight: 44"))
        #expect(action.contains(".contentShape(Rectangle())"))
    }

    @Test("README preview launch uses deterministic DerivedData")
    func readmePreviewLaunchIsPortable() throws {
        let readme = try self.source("README.md")

        #expect(readme.contains(#"-derivedDataPath "${TMPDIR%/}/ShipBarDerivedData""#))
        #expect(readme.contains(#"${TMPDIR%/}/ShipBarDerivedData/Build/Products/Debug/ShipBarMac.app"#))
        #expect(readme.contains("DerivedData/ShipBar-") == false)
    }

    private func source(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
