import AppKit
import SwiftData
import SwiftUI

@MainActor
final class QuickCapturePanelController: NSObject {
    private let modelContainer: ModelContainer
    private var panel: NSPanel?

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        super.init()
    }

    func show(relativeTo statusButton: NSStatusBarButton?) {
        if let panel = self.panel, panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        let panel = self.panel ?? self.makePanel()
        self.panel = panel

        if let origin = self.preferredOrigin(near: statusButton, panelSize: panel.frame.size) {
            panel.setFrameOrigin(origin)
        } else {
            panel.center()
        }

        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        self.panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let rootView = QuickCapturePanelView(
            container: self.modelContainer,
            dismiss: { [weak self] in self?.dismiss() })
            .modelContainer(self.modelContainer)
            .frame(width: 460)
            .fixedSize(horizontal: false, vertical: true)

        let hosting = NSHostingController(rootView: rootView)
        hosting.view.layoutSubtreeIfNeeded()
        let fittingHeight = max(72, hosting.view.fittingSize.height)
        let contentRect = NSRect(x: 0, y: 0, width: 460, height: fittingHeight)

        let panel = QuickCapturePanel(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        panel.contentViewController = hosting
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isMovableByWindowBackground = false
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.onResignKey = { [weak self] in self?.dismiss() }
        return panel
    }

    private func preferredOrigin(near statusButton: NSStatusBarButton?, panelSize: NSSize) -> NSPoint? {
        guard let button = statusButton,
              let buttonWindow = button.window
        else { return nil }
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let originX = buttonFrame.midX - (panelSize.width / 2)
        let originY = buttonFrame.minY - panelSize.height - 6
        return NSPoint(x: max(originX, 8), y: originY)
    }
}

private final class QuickCapturePanel: NSPanel {
    var onResignKey: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        self.onResignKey?()
    }

    override func cancelOperation(_ sender: Any?) {
        self.orderOut(nil)
    }
}

private struct QuickCapturePanelView: View {
    let container: ModelContainer
    let dismiss: () -> Void
    @Query(sort: \Project.sortOrder) private var projects: [Project]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(spacing: 0) {
            QuickCaptureView(
                projects: self.projects,
                selectedProjectID: nil,
                createTask: self.createTask)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
        }
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: Color.black.opacity(0.18), radius: 18, x: 0, y: 8)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .padding(6)
        .onReceive(NotificationCenter.default.publisher(for: .shipBarQuickCaptureSubmitted)) { _ in
            self.dismiss()
        }
    }

    private func createTask(from draft: CaptureDraft) {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let project = draft.projectID.flatMap { id in self.projects.first { $0.id == id } }
        let task = ShipTask(
            title: title,
            prompt: draft.prompt,
            status: draft.status,
            priority: draft.priority,
            type: draft.type,
            isInbox: project == nil,
            sourceApp: draft.sourceApp,
            sourceURL: draft.sourceURL,
            rawCaptureText: draft.rawText,
            project: project)
        self.modelContext.insert(task)
        try? self.modelContext.save()
        NotificationCenter.default.post(name: .shipBarQuickCaptureSubmitted, object: nil)
    }
}
