import SwiftUI

struct QuickCaptureView: View {
    let projects: [Project]
    let selectedProjectID: String?
    let createTask: (CaptureDraft) -> Void
    var autoFocus = false
    @State private var input = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(ShipBarStyle.accent)
                .font(.system(size: 15, weight: .semibold))
                .padding(.top, 2)

            TextField("Capture a task, paste a list, or add prompt after |", text: self.$input, axis: .vertical)
                .font(.system(size: 13))
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused(self.$isFocused)
                .onSubmit(self.submit)

            Button(action: self.submit) {
                Image(systemName: "arrow.turn.down.left")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(self.trimmedInput.isEmpty ? Color.secondary.opacity(0.45) : ShipBarStyle.accent)
            .disabled(self.trimmedInput.isEmpty)
            .padding(.top, 2)
            .accessibilityLabel("Submit Capture")
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .shipBarGlass(radius: ShipBarStyle.controlRadius, shadow: true)
        .task {
            guard self.autoFocus else { return }
            self.isFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .shipBarOpenCapture)) { _ in
            self.isFocused = true
        }
    }

    private var trimmedInput: String {
        self.input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submit() {
        guard !self.trimmedInput.isEmpty else { return }
        let projectTokens = self.projects.map(\.token)
        let drafts = CaptureBatchParser.parse(self.trimmedInput, projects: projectTokens)
        for var draft in drafts {
            if draft.projectID == nil {
                draft.projectID = self.selectedProjectID
            }
            self.createTask(draft)
        }
        self.input = ""
    }
}
