import AppKit
import SwiftData
import SwiftUI

@MainActor
final class VoicePanelController: NSObject {
    // The panel owns one VoiceSession for its lifetime so hiding/showing does
    // not rebuild UI state unnecessarily, while dismiss still stops audio.
    private let modelContainer: ModelContainer
    private let session: VoiceSession
    private var panel: NSPanel?

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.session = VoiceSession(modelContainer: modelContainer)
        super.init()
    }

    func toggle(relativeTo statusButton: NSStatusBarButton?) {
        if let panel = self.panel, panel.isVisible {
            self.dismiss()
        } else {
            self.show(relativeTo: statusButton)
        }
    }

    func show(relativeTo statusButton: NSStatusBarButton?) {
        let panel = self.panel ?? self.makePanel()
        self.panel = panel

        if let origin = self.preferredOrigin(near: statusButton, panelSize: panel.frame.size) {
            panel.setFrameOrigin(origin)
        } else {
            panel.center()
        }

        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        // Opening the panel starts capture immediately. Closing it is the
        // privacy boundary and tears down both AVAudioEngine and WebSocket.
        self.session.start()
    }

    func dismiss() {
        self.session.stop()
        self.panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let view = VoicePanelView(session: self.session, onClose: { [weak self] in self?.dismiss() })
            .frame(width: 460, height: 360)

        let hosting = NSHostingController(rootView: view)
        let contentRect = NSRect(x: 0, y: 0, width: 460, height: 360)

        let panel = VoicePanel(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        panel.contentViewController = hosting
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        return panel
    }

    private func preferredOrigin(near statusButton: NSStatusBarButton?, panelSize: NSSize) -> NSPoint? {
        guard let button = statusButton, let buttonWindow = button.window else { return nil }
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let originX = buttonFrame.midX - (panelSize.width / 2)
        let originY = buttonFrame.minY - panelSize.height - 6
        return NSPoint(x: max(originX, 8), y: originY)
    }
}

private final class VoicePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        // Esc should behave like dismissing the floating capture UI.
        self.orderOut(nil)
    }
}

private struct VoicePanelView: View {
    @ObservedObject var session: VoiceSession
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            self.header
            Divider()
            self.transcript
            Divider()
            self.footer
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
    }

    private var header: some View {
        HStack(spacing: 10) {
            self.indicator
            VStack(alignment: .leading, spacing: 1) {
                Text("Voice Capture")
                    .font(.system(size: 13, weight: .semibold))
                Text(self.statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: self.onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var indicator: some View {
        // `lastMicLevel` is intentionally only visual feedback. Voice activity
        // decisions come from server VAD, not this local meter.
        let level = min(max(CGFloat(self.session.lastMicLevel) * 6, 0), 1)
        return ZStack {
            Circle()
                .fill(self.indicatorColor.opacity(0.18))
                .frame(width: 28, height: 28)
            Circle()
                .fill(self.indicatorColor.opacity(0.35))
                .frame(width: 28 + level * 18, height: 28 + level * 18)
                .animation(.linear(duration: 0.08), value: level)
            Image(systemName: "mic.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(self.indicatorColor)
        }
        .frame(width: 48, height: 48)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if self.session.entries.isEmpty {
                        Text("Say something — for example: 'Add a task to ship Sentry to LEARN-X, high priority.'")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }
                    ForEach(self.session.entries) { entry in
                        self.row(for: entry)
                            .id(entry.id)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .onChange(of: self.session.entries.count) { _, _ in
                if let last = self.session.entries.last {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: self.session.entries.last?.text) { _, _ in
                if let last = self.session.entries.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private func row(for entry: TranscriptEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            self.rowIcon(for: entry.role)
                .frame(width: 18)
            Text(entry.text)
                .font(.system(size: 13))
                .foregroundStyle(self.rowColor(for: entry.role))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func rowIcon(for role: TranscriptEntry.Role) -> some View {
        switch role {
        case .user:
            Image(systemName: "person.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.blue)
        case .assistant:
            Image(systemName: "sparkles")
                .font(.system(size: 13))
                .foregroundStyle(Color.purple)
        case .tool:
            Image(systemName: "wrench.adjustable.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color.green)
        }
    }

    private func rowColor(for role: TranscriptEntry.Role) -> Color {
        switch role {
        case .user: .primary
        case .assistant: .primary
        case .tool: .secondary
        }
    }

    private var footer: some View {
        HStack {
            Text("⌘⇧V to dismiss")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var statusText: String {
        // "mic active" means local PCM chunks are arriving; it does not prove
        // the Realtime server has accepted or transcribed a turn.
        switch self.session.state {
        case .idle: "Idle"
        case .connecting: "Connecting…"
        case .listening:
            if let last = self.session.lastMicChunkAt, Date().timeIntervalSince(last) < 1.5 {
                "Listening · mic active"
            } else {
                "Listening · waiting for mic…"
            }
        case .responding: "Responding"
        case let .error(message): message
        }
    }

    private var indicatorColor: Color {
        switch self.session.state {
        case .idle: .secondary
        case .connecting: .orange
        case .listening: .green
        case .responding: .purple
        case .error: .red
        }
    }
}
