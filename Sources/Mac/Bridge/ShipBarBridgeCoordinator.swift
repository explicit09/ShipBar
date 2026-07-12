import Foundation
import SwiftData

/// Watches the App Group bridge queue while ShipBar runs: scans at
/// launch, on the helper's distributed notification, and on a fallback
/// timer so a missed notification cannot strand a request.
@MainActor
final class ShipBarBridgeCoordinator {
    static let requestNotification = Notification.Name("com.tadies.ShipBar.bridge.request")

    private let processor: ShipBarBridgeProcessor
    private var fallbackTimer: Timer?
    private var observer: NSObjectProtocol?

    init?(modelContainer: ModelContainer) {
        guard let store = try? ShipBarBridgeStore.appGroup() else { return nil }
        self.processor = ShipBarBridgeProcessor(store: store, modelContainer: modelContainer)
    }

    func start(fallbackInterval: TimeInterval = 5) {
        self.scan()
        self.observer = DistributedNotificationCenter.default().addObserver(
            forName: Self.requestNotification,
            object: nil,
            queue: .main)
        { _ in
            Task { @MainActor in
                ShipBarBridgeCoordinatorRegistry.shared?.scan()
            }
        }
        let timer = Timer(timeInterval: fallbackInterval, repeats: true) { _ in
            Task { @MainActor in
                ShipBarBridgeCoordinatorRegistry.shared?.scan()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.fallbackTimer = timer
        ShipBarBridgeCoordinatorRegistry.shared = self
    }

    func scan() {
        do {
            try self.processor.processPending()
        } catch {
            print("ShipBar bridge scan failed: \(error)")
        }
    }

    func stop() {
        self.fallbackTimer?.invalidate()
        self.fallbackTimer = nil
        if let observer {
            DistributedNotificationCenter.default().removeObserver(observer)
            self.observer = nil
        }
    }
}

@MainActor
enum ShipBarBridgeCoordinatorRegistry {
    static weak var shared: ShipBarBridgeCoordinator?
}
