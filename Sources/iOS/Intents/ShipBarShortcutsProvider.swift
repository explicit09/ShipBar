import AppIntents

struct ShipBarShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureInShipBarIntent(),
            phrases: [
                "Capture in \(.applicationName)",
                "Add a task to \(.applicationName)",
            ],
            shortTitle: "Capture",
            systemImageName: "tray.and.arrow.down.fill")
        AppShortcut(
            intent: ShowShipBarInboxIntent(),
            phrases: ["Show my \(.applicationName) inbox"],
            shortTitle: "Inbox",
            systemImageName: "tray.fill")
        AppShortcut(
            intent: ShowFlightPlanIntent(),
            phrases: ["Show my \(.applicationName) flight plan"],
            shortTitle: "Flight Plan",
            systemImageName: "sun.max.fill")
    }
}
