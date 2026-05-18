#if os(iOS)
import SwiftUI

struct IOSVoiceCaptureView: View {
    @ObservedObject var session: VoiceSession
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            self.header
            Divider()
            self.transcript
            Divider()
            self.controls
        }
        .onAppear {
            self.session.start()
        }
        .onDisappear {
            self.session.stop()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            self.indicator
            VStack(alignment: .leading, spacing: 2) {
                Text("Voice Capture")
                    .font(.system(size: 20, weight: .semibold))
                Text(self.statusText)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button(action: self.onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close Voice Capture")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    private var indicator: some View {
        let level = min(max(CGFloat(self.session.lastMicLevel) * 6, 0), 1)
        return ZStack {
            Circle()
                .fill(self.indicatorColor.opacity(0.14))
                .frame(width: 56, height: 56)
            Circle()
                .fill(self.indicatorColor.opacity(0.24))
                .frame(width: 36 + level * 26, height: 36 + level * 26)
                .animation(.linear(duration: 0.08), value: level)
            Image(systemName: "mic.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(self.indicatorColor)
        }
        .frame(width: 64, height: 64)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if self.session.entries.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Ready for voice commands", systemImage: "waveform")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Say something like: Add a high priority task to LEARN-X to fix the mobile capture flow.")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 12)
                    }

                    ForEach(self.session.entries) { entry in
                        self.row(for: entry)
                            .id(entry.id)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
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
        HStack(alignment: .top, spacing: 10) {
            self.rowIcon(for: entry.role)
                .frame(width: 22)
            Text(entry.text)
                .font(.system(size: 14))
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
                .font(.system(size: 18))
                .foregroundStyle(.blue)
        case .assistant:
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.purple)
        case .tool:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(ShipBarStyle.promptGreen)
        }
    }

    private func rowColor(for role: TranscriptEntry.Role) -> Color {
        switch role {
        case .user, .assistant:
            .primary
        case .tool:
            .secondary
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                if self.session.isActive {
                    self.session.stop()
                } else {
                    self.session.start()
                }
            } label: {
                Label(self.primaryActionTitle, systemImage: self.primaryActionIcon)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button("Close", action: self.onClose)
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
        .padding(18)
    }

    private var statusText: String {
        switch self.session.state {
        case .idle:
            "Idle"
        case .connecting:
            "Connecting..."
        case .listening:
            if let last = self.session.lastMicChunkAt, Date().timeIntervalSince(last) < 1.5 {
                "Listening - mic active"
            } else {
                "Listening - waiting for mic"
            }
        case .responding:
            "Responding"
        case let .error(message):
            message
        }
    }

    private var primaryActionTitle: String {
        switch self.session.state {
        case .idle:
            "Start Listening"
        case .connecting, .listening, .responding:
            "Stop Listening"
        case .error:
            "Try Again"
        }
    }

    private var primaryActionIcon: String {
        switch self.session.state {
        case .idle, .error:
            "mic.fill"
        case .connecting, .listening, .responding:
            "stop.fill"
        }
    }

    private var indicatorColor: Color {
        switch self.session.state {
        case .idle:
            .secondary
        case .connecting:
            .orange
        case .listening:
            ShipBarStyle.promptGreen
        case .responding:
            .purple
        case .error:
            .red
        }
    }
}
#endif
