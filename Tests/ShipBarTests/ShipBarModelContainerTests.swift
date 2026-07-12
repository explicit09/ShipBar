import Foundation
import Testing

@Suite("ShipBar model container")
struct ShipBarModelContainerTests {
    @Test("the on-disk store keeps its existing filename")
    func storeURLKeepsExistingFilename() {
        // Renaming this file would orphan every task the user already
        // has, so the name is part of the contract, not an implementation
        // detail.
        #expect(ShipBarModelContainer.storeURL().lastPathComponent == "default.store")
    }

    @Test("the store location is pinned explicitly, not inferred")
    func storeURLIsPinnedInSource() throws {
        // With an App Group entitlement present, letting CoreData infer
        // the store location deadlocks CloudKit mirroring while adding
        // the persistent store, and the app never finishes launching.
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/Shared/Persistence/ShipBarModelContainer.swift"),
            encoding: .utf8)

        #expect(source.contains("url: Self.storeURL()"))
    }
}
