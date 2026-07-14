import Foundation
import SwiftData

/// Watches ShipBar's private Mac bridge queue while ShipBar runs: scans at
/// launch, on the helper's distributed notification, and on a fallback
/// timer so a missed notification cannot strand a request.
@MainActor
final class ShipBarBridgeCoordinator {
    static let requestNotification = Notification.Name("com.tadies.ShipBar.bridge.request")

    private let processor: ShipBarBridgeProcessor
    private var fallbackTimer: Timer?
    private var observer: NSObjectProtocol?

    /// Fails only when ShipBar's application container is unreachable, which
    /// means the bridge genuinely cannot work in this process. The
    /// reason is recorded rather than swallowed so a silent no-op
    /// coordinator can never masquerade as a working bridge.
    private(set) static var unavailableReason: String?

    init?(modelContainer: ModelContainer) {
        do {
            let store = try ShipBarBridgeStore.macApplicationSupport()
            self.processor = ShipBarBridgeProcessor(store: store, modelContainer: modelContainer)
            Self.unavailableReason = nil
        } catch {
            let reason = error.localizedDescription
            Self.unavailableReason = reason
            Self.writeDiagnostic("bridge unavailable: \(reason)")
            return nil
        }
    }

    func start(fallbackInterval: TimeInterval = 5) {
        Self.writeDiagnostic("bridge started at \(self.processor.store.debugRootPath)")
        self.scan()

        // Both callbacks hold this coordinator strongly. The AppDelegate
        // owns it for the process lifetime, and routing through a weak
        // registry would silently stop the bridge if that lookup ever
        // came back nil.
        self.observer = DistributedNotificationCenter.default().addObserver(
            forName: Self.requestNotification,
            object: nil,
            queue: .main)
        { _ in
            MainActor.assumeIsolated { self.scan() }
        }
        let timer = Timer(timeInterval: fallbackInterval, repeats: true) { _ in
            MainActor.assumeIsolated { self.scan() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.fallbackTimer = timer
    }

    func scan() {
        do {
            let processed = try self.processor.processPending()
            if processed > 0 {
                Self.writeDiagnostic("bridge processed \(processed) request(s)")
            }
        } catch {
            Self.writeDiagnostic("bridge scan failed: \(error)")
        }
    }

    private static func writeDiagnostic(_ line: String) {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShipBarBridge.txt")
        let entry = "\(Date()) \(line)\n"
        guard let data = entry.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? entry.write(to: url, atomically: true, encoding: .utf8)
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
