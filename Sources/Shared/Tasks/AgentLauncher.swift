import Foundation

#if os(macOS)
import AppKit
#endif

enum AgentLauncher {
    static func open(_ target: AgentTarget, repoPath: String = "") {
        #if os(macOS)
        guard let path = Self.applicationPath(for: target) else { return }
        let url = URL(fileURLWithPath: path)
        let configuration = NSWorkspace.OpenConfiguration()
        let trimmedRepoPath = repoPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedRepoPath.isEmpty {
            let repoURL = URL(fileURLWithPath: trimmedRepoPath)
            NSWorkspace.shared.open([repoURL], withApplicationAt: url, configuration: configuration)
        } else {
            NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        }
        #endif
    }

    #if os(macOS)
    private static func applicationPath(for target: AgentTarget) -> String? {
        switch target {
        case .codex:
            "/Applications/Codex.app"
        case .claude:
            "/Applications/Terminal.app"
        case .cursor:
            "/Applications/Cursor.app"
        }
    }
    #endif
}
