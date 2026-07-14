import SwiftUI

struct ShipBarCommandPaletteView: View {
    let tasks: [ShipTask]
    let projects: [Project]
    let runs: [AgentRun]
    let execute: (ShipBarCommandResult) -> Void
    let dismiss: () -> Void
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var results: [ShipBarCommandResult] {
        ShipBarCommandSearch.results(
            query: self.query,
            tasks: self.tasks,
            projects: self.projects,
            runs: self.runs)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "command")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(ShipBarStyle.shipBlue)
                TextField("Find a task, project, run, or destination", text: self.$query)
                    .font(.system(size: 15, weight: .medium))
                    .textFieldStyle(.plain)
                    .focused(self.$searchFocused)
                    .onSubmit {
                        if let first = self.results.first { self.run(first) }
                    }
                #if os(macOS)
                ShipBarNavigationIconButton(
                    systemImage: "xmark",
                    accessibilityLabel: "Close command palette",
                    action: self.dismiss)
                #else
                Text("esc")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06)))
                #endif
            }
            .padding(13)

            Rectangle().fill(ShipBarStyle.separator).frame(height: 1)

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 3) {
                    if self.results.isEmpty {
                        Text("No matching ShipBar command")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                    } else {
                        ForEach(self.results) { result in
                            Button { self.run(result) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: result.systemImage)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(self.tint(for: result.kind))
                                        .frame(width: 24, height: 24)
                                        .background(Circle().fill(self.tint(for: result.kind).opacity(0.10)))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(result.title)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(result.subtitle)
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: "return")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(.quaternary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 390)

            HStack {
                Text("Type to search · Return opens first result")
                Spacer()
                Text("⌘K")
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.025))
        }
        .frame(maxWidth: 520)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.primary.opacity(0.12)))
        .shadow(color: .black.opacity(0.28), radius: 30, y: 14)
        .padding(16)
        .task { self.searchFocused = true }
        #if os(macOS)
        .onExitCommand(perform: self.dismiss)
        #endif
    }

    private func run(_ result: ShipBarCommandResult) {
        self.execute(result)
        self.dismiss()
    }

    private func tint(for kind: ShipBarCommandKind) -> Color {
        switch kind {
        case .navigation: ShipBarStyle.shipBlue
        case .project: ShipBarStyle.reviewAmber
        case .task: ShipBarStyle.successGreen
        case .run: ShipBarStyle.runPurple
        }
    }
}
