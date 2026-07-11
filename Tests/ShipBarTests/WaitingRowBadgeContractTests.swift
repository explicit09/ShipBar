import Foundation
import Testing

@Suite("Waiting row badge source contracts")
struct WaitingRowBadgeContractTests {
    @Test("Waiting badges retain their intrinsic one-line size")
    func waitingBadgesRetainIntrinsicSize() throws {
        let badgeSource = try self.source("Sources/Shared/Views/ShipBarStateBadge.swift")
        let rowSource = try self.source("Sources/Shared/Views/FocusTaskRowView.swift")

        #expect(badgeSource.contains(".lineLimit(1)"))
        #expect(badgeSource.contains(".fixedSize(horizontal: true, vertical: true)"))
        #expect(rowSource.contains("ShipBarStateBadge(runStatus: status)"))
        #expect(rowSource.contains(".layoutPriority(2)"))
    }

    private func source(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
