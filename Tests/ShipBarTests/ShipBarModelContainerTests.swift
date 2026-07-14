import Foundation
import Testing

private actor ManifestCASFixture {
    private var value = ShipBarDirectCloudSync.ManifestIDs()
    private var revision = 0

    func fetch() -> (ShipBarDirectCloudSync.ManifestIDs, Int) { (self.value, self.revision) }

    func compareAndSwap(
        expectedRevision: Int,
        value: ShipBarDirectCloudSync.ManifestIDs) -> Bool
    {
        guard self.revision == expectedRevision else { return false }
        self.value = value
        self.revision += 1
        return true
    }
}

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

    @Test("concurrent device manifest retries union both new record IDs")
    func concurrentManifestUnion() async {
        let cloud = ManifestCASFixture()
        let firstDevice = ShipBarDirectCloudSync.ManifestIDs(taskIDs: ["task-a"])
        let secondDevice = ShipBarDirectCloudSync.ManifestIDs(taskIDs: ["task-b"])

        func save(_ local: ShipBarDirectCloudSync.ManifestIDs) async {
            while true {
                let (remote, revision) = await cloud.fetch()
                await Task.yield()
                let merged = ShipBarDirectCloudSync.mergeManifest(remote: remote, local: local)
                if await cloud.compareAndSwap(expectedRevision: revision, value: merged) { return }
            }
        }
        async let first: Void = save(firstDevice)
        async let second: Void = save(secondDevice)
        _ = await (first, second)
        let (saved, _) = await cloud.fetch()

        #expect(saved.taskIDs == ["task-a", "task-b"])
    }
}
