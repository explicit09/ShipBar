import SwiftUI

struct QuickCaptureView: View {
    let projects: [Project]
    let selectedProjectID: String?
    let createTask: (CaptureDraft) -> Void
    @State private var input = ""

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(ShipBarStyle.accent)
                .font(.system(size: 15, weight: .semibold))

            TextField("Capture task or prompt...", text: self.$input)
                .font(.system(size: 13))
                .textFieldStyle(.plain)
                .onSubmit(self.submit)

            Button(action: self.submit) {
                Image(systemName: "arrow.turn.down.left")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(self.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary.opacity(0.45) : ShipBarStyle.accent)
            .disabled(self.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .shipBarGlass(radius: ShipBarStyle.controlRadius, shadow: true)
    }

    private func submit() {
        let projectTokens = self.projects.map(\.token)
        var draft = CaptureParser.parse(self.input, projects: projectTokens)
        if draft.projectID == nil {
            draft.projectID = self.selectedProjectID
        }
        self.createTask(draft)
        self.input = ""
    }
}
