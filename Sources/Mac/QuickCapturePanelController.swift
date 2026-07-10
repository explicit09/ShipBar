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
            NotificationCenter.default.post(name: .shipBarOpenCapture, object: nil)
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
        NotificationCenter.default.post(name: .shipBarOpenCapture, object: nil)
    }

    func dismiss() {
        self.panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let rootView = QuickCapturePanelView(
            container: self.modelContainer,
            dismiss: { [weak self] in self?.dismiss() })
            .modelContainer(self.modelContainer)
            .frame(width: 540)
            .fixedSize(horizontal: false, vertical: true)

        let hosting = NSHostingController(rootView: rootView)
        hosting.view.layoutSubtreeIfNeeded()
        let fittingHeight = max(140, hosting.view.fittingSize.height)
        let contentRect = NSRect(x: 0, y: 0, width: 540, height: fittingHeight)

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
    @State private var input = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            self.field
            self.parsePreview
            self.hintRow
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: Color.black.opacity(0.22), radius: 22, x: 0, y: 10)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .padding(8)
        .task {
            self.isFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .shipBarOpenCapture)) { _ in
            self.isFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .shipBarQuickCaptureSubmitted)) { _ in
            self.dismiss()
        }
    }

    private var field: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.tertiary)
            TextField("What are you shipping?", text: self.$input, axis: .vertical)
                .font(.system(size: 17, weight: .regular))
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .focused(self.$isFocused)
                .onSubmit(self.submit)
            if !self.trimmedInput.isEmpty {
                Button(action: self.submit) {
                    Image(systemName: "return")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.primary.opacity(0.08))
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var parsePreview: some View {
        let parsed = self.parsedDraft
        if let parsed, !parsed.isEmpty {
            HStack(spacing: 6) {
                if let projectChip = parsed.projectChip {
                    self.chip(label: projectChip, tint: ShipBarStyle.accent, systemImage: "folder.fill")
                }
                if let due = parsed.dueChip {
                    self.chip(label: due, tint: .orange, systemImage: "calendar")
                }
                if let priority = parsed.priorityChip {
                    self.chip(label: priority, tint: ShipBarStyle.priorityColor(parsed.draft.priority), systemImage: "flag.fill")
                }
                if let typeChip = parsed.typeChip {
                    self.chip(label: typeChip, tint: .secondary, systemImage: "tag.fill")
                }
                Spacer()
            }
        }
    }

    private var hintRow: some View {
        HStack(spacing: 12) {
            Text("Try")
                .foregroundStyle(.tertiary)
            Text("proj:learn-x")
                .foregroundStyle(.secondary)
                .monospaced()
            Text("·").foregroundStyle(.quaternary)
            Text("today")
                .foregroundStyle(.secondary)
                .monospaced()
            Text("·").foregroundStyle(.quaternary)
            Text("p1")
                .foregroundStyle(.secondary)
                .monospaced()
            Text("·").foregroundStyle(.quaternary)
            Text("bug")
                .foregroundStyle(.secondary)
                .monospaced()
            Spacer()
            Text("⏎ to capture · esc to dismiss")
                .foregroundStyle(.tertiary)
        }
        .font(.system(size: 11))
    }

    private func chip(label: String, tint: Color, systemImage: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(tint)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background {
            Capsule(style: .continuous)
                .fill(tint.opacity(0.12))
        }
        .overlay {
            Capsule(style: .continuous)
                .stroke(tint.opacity(0.25), lineWidth: 1)
        }
    }

    private var trimmedInput: String {
        self.input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsedDraft: ParsedPreview? {
        guard !self.trimmedInput.isEmpty else { return nil }
        let tokens = self.projects.map(\.token)
        let draft = CaptureParser.parse(self.trimmedInput, projects: tokens)
        return ParsedPreview(
            draft: draft,
            projects: self.projects)
    }

    private func submit() {
        guard !self.trimmedInput.isEmpty else { return }
        let tokens = self.projects.map(\.token)
        let drafts = CaptureBatchParser.parse(self.trimmedInput, projects: tokens)
        for draft in drafts {
            self.createTask(from: draft)
        }
        self.input = ""
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
            dueDate: draft.dueDate,
            isInbox: project == nil,
            sourceApp: draft.sourceApp,
            sourceURL: draft.sourceURL,
            rawCaptureText: draft.rawText,
            project: project)
        self.modelContext.insert(task)
        ShipBarPersistence.save(self.modelContext, operation: "Quick capture")
        NotificationCenter.default.post(name: .shipBarQuickCaptureSubmitted, object: nil)
    }
}

private struct ParsedPreview {
    let draft: CaptureDraft
    let projects: [Project]

    var isEmpty: Bool {
        self.projectChip == nil && self.dueChip == nil && self.priorityChip == nil && self.typeChip == nil
    }

    var projectChip: String? {
        guard let id = self.draft.projectID,
              let project = self.projects.first(where: { $0.id == id })
        else { return nil }
        return project.name
    }

    var dueChip: String? {
        guard let due = self.draft.dueDate else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let dueDay = calendar.startOfDay(for: due)
        let days = calendar.dateComponents([.day], from: today, to: dueDay).day ?? 0
        if days < 0 { return "Overdue" }
        if days == 0 { return "Today" }
        if days == 1 { return "Tomorrow" }
        if days < 7 { return due.formatted(.dateTime.weekday(.wide)) }
        return due.formatted(date: .abbreviated, time: .omitted)
    }

    var priorityChip: String? {
        switch self.draft.priority {
        case .high: "High"
        case .low: "Low"
        case .medium: nil
        }
    }

    var typeChip: String? {
        switch self.draft.type {
        case .idea: nil
        default: self.draft.type.label
        }
    }
}
