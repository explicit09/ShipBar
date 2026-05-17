import AppKit
import Combine
import SwiftData
import SwiftUI

@main
struct ShipBarMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            Text("ShipBar")
                .padding()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var hotKeyController: GlobalHotKeyController?
    private var menuController: StatusItemMenuController?
    private var capturePanel: QuickCapturePanelController?
    private var voicePanel: VoicePanelController?
    private var windowPresenter: WindowPresenter?
    private var inboxObserver: InboxCountObserver?
    private var inboxCancellable: AnyCancellable?
    private var writeContext: ModelContext?

    private lazy var modelContainer: ModelContainer = {
        do {
            return try ShipBarModelContainer.make()
        } catch {
            print("Unable to create CloudKit-backed ShipBar model container: \(error)")
            return try! ShipBarModelContainer.make(inMemory: true)
        }
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = notification
        NSApp.setActivationPolicy(.accessory)

        self.writeContext = ModelContext(self.modelContainer)
        self.seedDefaultProjectIfNeeded()

        let menuController = StatusItemMenuController(modelContainer: self.modelContainer)
        menuController.delegate = self
        self.menuController = menuController

        self.capturePanel = QuickCapturePanelController(modelContainer: self.modelContainer)
        self.voicePanel = VoicePanelController(modelContainer: self.modelContainer)
        self.windowPresenter = WindowPresenter(modelContainer: self.modelContainer)

        self.configureStatusItem()
        self.observeInbox()
        self.configureHotKey()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = StatusItemBadge.image(inboxCount: 0)
        item.button?.imagePosition = .imageLeft
        item.button?.target = self
        item.button?.action = #selector(self.statusItemClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        self.statusItem = item
    }

    private func observeInbox() {
        let observer = InboxCountObserver(modelContainer: self.modelContainer)
        self.inboxObserver = observer
        self.inboxCancellable = observer.$count
            .receive(on: RunLoop.main)
            .sink { [weak self] count in
                self?.statusItem?.button?.image = StatusItemBadge.image(inboxCount: count)
            }
    }

    private func configureHotKey() {
        let controller = GlobalHotKeyController()
        controller.register(.captureCmdShiftK) { [weak self] in
            self?.showQuickCapture()
        }
        controller.register(.voiceCmdShiftV) { [weak self] in
            self?.toggleVoiceCapture()
        }
        self.hotKeyController = controller
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let statusItem = self.statusItem,
              let menuController = self.menuController
        else { return }
        let menu = menuController.buildMenu()
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func showQuickCapture() {
        self.capturePanel?.show(relativeTo: self.statusItem?.button)
    }

    private func toggleVoiceCapture() {
        self.voicePanel?.toggle(relativeTo: self.statusItem?.button)
    }

    private func promptForAPIKey() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "OpenAI API Key"
        alert.informativeText = "Used for voice capture (gpt-realtime-2). Stored in your Keychain."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 22))
        field.placeholderString = "sk-…"
        field.stringValue = KeychainStore.openAIKey() ?? ""
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        KeychainStore.setOpenAIKey(value.isEmpty ? nil : value)
    }

    private func seedDefaultProjectIfNeeded() {
        guard let context = self.writeContext else { return }
        let descriptor = FetchDescriptor<Project>()
        let existing = (try? context.fetch(descriptor)) ?? []
        guard existing.isEmpty else { return }
        let defaults = [
            ("LEARN-X", "purple", "You are working in the LEARN-X repository. Keep learning flows concise and useful."),
            ("vedit", "green", "You are working in the vedit repository. Build robust, maintainable video editing workflows."),
            ("Technologia", "orange", "You are working on Technologia. Keep writing clear, specific, and shippable."),
        ]
        for (index, project) in defaults.enumerated() {
            context.insert(Project(
                name: project.0,
                basePrompt: project.2,
                color: project.1,
                sortOrder: index))
        }
        try? context.save()
    }
}

extension AppDelegate: StatusItemMenuDelegate {
    func menuDidRequestQuickCapture() {
        self.showQuickCapture()
    }

    func menuDidRequestVoiceCapture() {
        self.toggleVoiceCapture()
    }

    func menuDidRequestSetAPIKey() {
        self.promptForAPIKey()
    }

    func menuDidRequestOpenWindow() {
        self.windowPresenter?.openMain()
    }

    func menuDidRequestSettings() {
        self.windowPresenter?.openMain()
    }

    func menuDidRequestQuit() {
        NSApp.terminate(nil)
    }

    func menuDidRequestNewProject() {
        guard let context = self.writeContext else { return }
        let descriptor = FetchDescriptor<Project>()
        let existing = (try? context.fetch(descriptor)) ?? []
        let project = Project(name: "New Project", sortOrder: existing.count)
        context.insert(project)
        try? context.save()
        self.windowPresenter?.openMain()
    }

    func menuDidSelectTask(_ task: ShipTask) {
        self.windowPresenter?.openTask(task)
    }

    func menuDidToggleDone(_ task: ShipTask) {
        guard let context = self.writeContext else { return }
        if let live = context.model(for: task.persistentModelID) as? ShipTask {
            live.applyStatus(live.status == .done ? .todo : .done)
            try? context.save()
        }
    }

    func menuDidHandoffTask(_ task: ShipTask, to target: AgentTarget) {
        guard let context = self.writeContext else { return }
        guard let live = context.model(for: task.persistentModelID) as? ShipTask else { return }
        let action = live.beginAgentHandoff(to: target)
        Clipboard.copy(action.clipboardText)
        AgentLauncher.open(target, repoPath: action.repoPath)
        try? context.save()
    }
}
