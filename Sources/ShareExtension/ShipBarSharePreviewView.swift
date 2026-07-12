import SwiftUI

struct ShipBarSharePreviewView: View {
    let payload: SharedCapturePayload
    let complete: () -> Void
    let cancel: () -> Void

    @State private var title: String
    @State private var draft: CaptureDraft
    @State private var isStructured: Bool
    @State private var queueState = QueueState.reviewing

    private enum QueueState: Equatable {
        case reviewing
        case queued
        case failed(String)
    }

    init(payload: SharedCapturePayload, complete: @escaping () -> Void, cancel: @escaping () -> Void) {
        self.payload = payload
        self.complete = complete
        self.cancel = cancel
        let trimmed = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let structured = StructuredCaptureParser.parse(trimmed, projects: [])
        let initialDraft = structured ?? payload.captureDraft(projects: [])
        self._draft = State(initialValue: initialDraft)
        self._isStructured = State(initialValue: structured != nil)
        self._title = State(initialValue: initialDraft.title)
    }

    var body: some View {
        NavigationStack {
            Form {
                switch self.queueState {
                case .queued:
                    Label("Queued for ShipBar", systemImage: "tray.and.arrow.down.fill")
                        .font(.headline)
                    Text("It will finish syncing when ShipBar opens.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                case .failed(let message):
                    Label("Could not queue", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(.red)
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                case .reviewing:
                    Section("Task") {
                        TextField("Title", text: self.$title, axis: .vertical)
                            .lineLimit(1 ... 3)
                    }
                    Section("Details") {
                        LabeledContent(
                            "Project",
                            value: self.draft.projectHint.isEmpty ? "Inbox" : self.draft.projectHint)
                        LabeledContent("Priority", value: self.draft.priority.label)
                        LabeledContent(
                            "Agent prompt",
                            value: self.draft.prompt.isEmpty ? "None" : "Detected")
                    }
                }
            }
            .navigationTitle("Save to ShipBar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: self.cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if self.queueState == .reviewing {
                        Button("Save", action: self.save)
                            .disabled(self.trimmedTitle.isEmpty)
                    } else {
                        Button("Done", action: self.complete)
                    }
                }
            }
        }
    }

    private var trimmedTitle: String {
        self.title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        var queued = self.payload
        var reviewedDraft = self.draft
        reviewedDraft.title = self.trimmedTitle
        if self.isStructured || reviewedDraft.title != self.draft.title {
            if !self.isStructured {
                reviewedDraft.taskDescription = self.payload.text
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            queued.normalizedText = StructuredCaptureParser.normalizedText(from: reviewedDraft)
        }
        do {
            try SharedCaptureStore.appendToSharedContainer(queued)
            self.queueState = .queued
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                self.complete()
            }
        } catch {
            self.queueState = .failed(error.localizedDescription)
        }
    }
}
