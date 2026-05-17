import Combine
import Foundation
import SwiftData

@MainActor
final class InboxCountObserver: ObservableObject {
    @Published private(set) var count: Int = 0

    private let modelContext: ModelContext
    private var cancellable: AnyCancellable?

    init(modelContainer: ModelContainer) {
        self.modelContext = ModelContext(modelContainer)
        self.refresh()

        self.cancellable = NotificationCenter.default
            .publisher(for: ModelContext.didSave)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refresh()
            }
    }

    func refresh() {
        let descriptor = FetchDescriptor<ShipTask>()
        let fetched = (try? self.modelContext.fetch(descriptor)) ?? []
        self.count = fetched.filter { $0.isInbox && $0.status != .done }.count
    }
}
