import Foundation
import Testing

@Suite("Final review source contracts")
struct FinalReviewContractTests {
    @Test("production apps never seed personal-looking projects")
    func productionAppsDoNotSeedProjects() throws {
        let mac = try self.source("Sources/Mac/ShipBarMacApp.swift")
        let root = try self.source("Sources/Shared/Views/ShipBarRootView.swift")
        let defaults = try self.source("Sources/Shared/Persistence/ShipBarDefaultData.swift")

        #expect(mac.contains("seedDefaultProjectIfNeeded") == false)
        #expect(root.contains("seedDefaultProjectIfNeeded") == false)
        #expect(defaults.contains("static func seedProjectsIfNeeded") == false)
    }

    @Test("selected and focused surfaces use graphite instead of saturated blue")
    func selectedSurfacesUseGraphite() throws {
        let style = try self.source("Sources/Shared/Views/ShipBarStyle.swift")
        let command = try self.source("Sources/Shared/Views/ShipBarCommandStrip.swift")
        let dock = try self.source("Sources/Shared/Views/ShipBarDestinationDock.swift")
        let focusRow = try self.source("Sources/Shared/Views/FocusTaskRowView.swift")
        let today = try self.source("Sources/Shared/Views/TodayCommandCenterView.swift")
        let stateBadge = try self.source("Sources/Shared/Views/ShipBarStateBadge.swift")

        #expect(style.contains("static var selectionSurface: Color { Color.primary.opacity"))
        #expect(style.contains("static var selectionStroke: Color"))
        #expect(style.contains("static var selectionForeground: Color"))
        #expect(command.contains(".focusEffectDisabled()"))
        #expect(dock.contains(".focusEffectDisabled()"))
        for source in [command, dock, focusRow, today] {
            #expect(source.contains("ShipBarStyle.shipBlue") == false)
        }
        #expect(stateBadge.contains("case .prepared: ShipBarStyle.selectionForeground"))
    }


    @Test("Mac project workspace exposes explicit return navigation")
    func macProjectWorkspaceExposesReturnNavigation() throws {
        let workspace = try self.source("Sources/Shared/Views/ProjectWorkspaceView.swift")
        let root = try self.source("Sources/Shared/Views/ShipBarRootView.swift")

        #expect(workspace.contains("let backToProjects: () -> Void"))
        #expect(workspace.contains("ShipBarNavigationIconButton(\n                systemImage: \"chevron.left\",\n                accessibilityLabel: \"Back to Projects\""))
        #expect(root.contains("backToProjects: { self.selectedProjectID = nil }"))
    }

    @Test("Every nested Mac surface exposes an explicit navigation icon")
    func everyNestedMacSurfaceExposesNavigationIcon() throws {
        let workspace = try self.source("Sources/Shared/Views/ProjectWorkspaceView.swift")
        let windows = try self.source("Sources/Mac/WindowPresenter.swift")
        let review = try self.source("Sources/Shared/Views/AgentRunReviewView.swift")
        let palette = try self.source("Sources/Shared/Views/ShipBarCommandPaletteView.swift")
        let root = try self.source("Sources/Shared/Views/ShipBarRootView.swift")

        #expect(workspace.contains("ShipBarNavigationIconButton(\n                systemImage: \"chevron.left\",\n                accessibilityLabel: \"Back to Projects\""))
        #expect(windows.contains("accessibilityLabel: \"Close task details\""))
        #expect(review.contains("accessibilityLabel: \"Close run review\""))
        #expect(palette.contains("accessibilityLabel: \"Close command palette\""))
        #expect(root.contains("accessibilityLabel: \"Cancel capture\""))
        #expect(root.contains("accessibilityLabel: \"Close settings\""))
    }

    @Test("iOS command palette keeps escape badge styling")
    func iOSCommandPaletteKeepsEscapeBadgeStyling() throws {
        let palette = try self.source("Sources/Shared/Views/ShipBarCommandPaletteView.swift")

        #expect(palette.contains("Text(\"esc\")\n                    .font(.system(size: 9, weight: .semibold, design: .monospaced))\n                    .foregroundStyle(.tertiary)\n                    .padding(.horizontal, 6)\n                    .padding(.vertical, 3)\n                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06)))"))
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

    @Test("Flight Plan rows contain long titles without changing workflow rows")
    func flightPlanRowsContainLongTitles() throws {
        let row = try self.source("Sources/Shared/Views/FocusTaskRowView.swift")

        #expect(row.contains(".lineLimit(self.isFlightPlan ? 1 : 2)"))
        #expect(row.contains(".truncationMode(.tail)"))
        #expect(row.contains(".frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)"))
        #expect(row.contains(".frame(maxWidth: .infinity)"))
        #expect(row.contains(".frame(height: self.isFlightPlan ? 48 : nil)"))
        #expect(row.contains(".help(self.task.title)"))
    }

    @Test("Mac navigation buttons are icon only, accessible, and easy to hit")
    func macNavigationButtonsAreAccessibleIconOnlyControls() throws {
        let button = try self.source("Sources/Mac/ShipBarNavigationIconButton.swift")

        #expect(button.contains("struct ShipBarNavigationIconButton: View"))
        #expect(button.contains("Image(systemName: self.systemImage)"))
        #expect(button.contains(".frame(width: 44, height: 44)"))
        #expect(button.contains(".contentShape(Rectangle())"))
        #expect(button.contains(".accessibilityLabel(self.accessibilityLabel)"))
        #expect(button.contains(".help(self.accessibilityLabel)"))
    }

    private func source(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
