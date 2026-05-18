import AppKit
import SwiftData
import SwiftUI

@MainActor
final class WindowPresenter: NSObject {
    private let modelContainer: ModelContainer
    private var taskWindows: [String: NSWindow] = [:]
    private var mainWindow: NSWindow?

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        super.init()
    }

    func openMain() {
        if let window = self.mainWindow {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }

        let root = ShipBarRootView()
            .modelContainer(self.modelContainer)
            .frame(minWidth: 380, minHeight: 580)

        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = "ShipBar"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 420, height: 620))
        window.center()
        window.delegate = self

        self.mainWindow = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func openTask(_ task: ShipTask) {
        let taskID = task.id
        if let window = self.taskWindows[taskID] {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }

        let root = TaskDetailWindowView(
            taskID: taskID,
            onClose: { [weak self] in self?.closeTask(taskID: taskID) },
            onDelete: { [weak self] in self?.closeTask(taskID: taskID) })
            .modelContainer(self.modelContainer)
            .frame(minWidth: 520, minHeight: 540)

        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = task.title.isEmpty ? "Task" : task.title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 560, height: 620))
        window.center()
        window.delegate = self
        window.identifier = NSUserInterfaceItemIdentifier("ShipBarTask:\(taskID)")

        self.taskWindows[taskID] = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func closeTask(taskID: String) {
        guard let window = self.taskWindows.removeValue(forKey: taskID) else { return }
        window.close()
    }
}

extension WindowPresenter: NSWindowDelegate {
    nonisolated func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.mainWindow === window {
                self.mainWindow = nil
                return
            }
            if let entry = self.taskWindows.first(where: { $0.value === window }) {
                self.taskWindows.removeValue(forKey: entry.key)
            }
        }
    }
}

private struct TaskDetailWindowView: View {
    let taskID: String
    let onClose: () -> Void
    let onDelete: () -> Void
    @Query private var tasks: [ShipTask]
    @Query(sort: \Project.sortOrder) private var projects: [Project]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        if let task = self.tasks.first(where: { $0.id == self.taskID }) {
            TaskDetailView(task: task, projects: self.projects) {
                self.modelContext.delete(task)
                try? self.modelContext.save()
                self.onDelete()
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
                Text("This task is no longer available.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear(perform: self.onClose)
        }
    }
}
