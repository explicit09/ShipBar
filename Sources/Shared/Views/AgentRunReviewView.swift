import SwiftData
import SwiftUI

struct AgentRunReviewView: View {
    @Bindable var run: AgentRun
    let task: ShipTask?
    let save: () -> Void
    let accept: (AgentRun, ShipTask?) -> Void
    let requestChanges: (AgentRun, ShipTask) -> Void
    let fail: (AgentRun) -> Void
    let cancel: (AgentRun) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showPrompt = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                self.header
                self.resultSection
                self.evidenceSection
                self.promptSection
                if !self.run.errorMessage.isEmpty { self.errorSection }
                self.actions
            }
            .padding(20)
        }
        #if os(macOS)
        .frame(minWidth: 500, idealWidth: 560, minHeight: 520, idealHeight: 620)
        #endif
        .onChange(of: self.run.resultSummary) { _, _ in self.save() }
        .onChange(of: self.run.evidenceURLString) { _, _ in self.save() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                ShipBarStateBadge(runStatus: self.run.status)
                Spacer()
                Text(self.run.target?.label ?? "Unknown agent")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Text(self.run.taskTitleSnapshot)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .tracking(-0.4)
            HStack(spacing: 5) {
                Text(self.run.projectNameSnapshot ?? "No project")
                if !self.run.repositoryPathSnapshot.isEmpty {
                    Text("·")
                    Text(self.run.repositoryPathSnapshot)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
        }
    }

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            self.sectionLabel("Result summary", icon: "text.alignleft")
            TextEditor(text: self.$run.resultSummary)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 94)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(ShipBarStyle.raisedSurface))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(ShipBarStyle.subtleStroke))
                .overlay(alignment: .topLeading) {
                    if self.run.resultSummary.isEmpty {
                        Text("Record what came back and what still needs attention.")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .padding(15)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    private var evidenceSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            self.sectionLabel("Evidence", icon: "link")
            TextField("Commit, pull request, report, or local file URL", text: self.$run.evidenceURLString)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 9).fill(ShipBarStyle.raisedSurface))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(ShipBarStyle.subtleStroke))
        }
    }

    private var promptSection: some View {
        DisclosureGroup(isExpanded: self.$showPrompt) {
            Text(self.run.promptSnapshot)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(11)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.black.opacity(0.12)))
                .padding(.top, 7)
        } label: {
            self.sectionLabel("Prompt snapshot", icon: "doc.text")
        }
        .tint(.secondary)
    }

    private var errorSection: some View {
        Label(self.run.errorMessage, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.red)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.red.opacity(0.08)))
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 8) {
            if self.run.status == .needsReview {
                Button("Accept and complete", systemImage: "checkmark.circle.fill") {
                    self.accept(self.run, self.task)
                    self.dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(ShipBarStyle.successGreen)

                if let task {
                    Button("Request changes") {
                        self.requestChanges(self.run, task)
                        self.dismiss()
                    }
                    .buttonStyle(.bordered)
                }
            }

            Spacer()

            if [.prepared, .handedOff, .running, .needsReview].contains(self.run.status) {
                Menu {
                    Button("Mark failed", systemImage: "exclamationmark.triangle", role: .destructive) {
                        self.fail(self.run)
                        self.dismiss()
                    }
                    Button("Cancel run", systemImage: "xmark.circle", role: .destructive) {
                        self.cancel(self.run)
                        self.dismiss()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }

    private func sectionLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.secondary)
    }
}
