import Foundation
import SwiftData
import SwiftUI

enum VoiceSessionState {
    case idle
    case connecting
    case listening
    case responding
    case error(String)
}

struct TranscriptEntry: Identifiable {
    enum Role {
        case user
        case assistant
        case tool
    }

    let id: String
    var role: Role
    var text: String
    var isStreaming: Bool

    init(id: String = UUID().uuidString, role: Role, text: String, isStreaming: Bool = false) {
        self.id = id
        self.role = role
        self.text = text
        self.isStreaming = isStreaming
    }
}

@MainActor
final class VoiceSession: ObservableObject {
    // Orchestrates the voice feature: UI state, audio pipeline, Realtime
    // transport, and local tool execution. The lower layers stay reusable.
    @Published private(set) var state: VoiceSessionState = .idle
    @Published private(set) var entries: [TranscriptEntry] = []
    @Published private(set) var lastMicChunkAt: Date?
    @Published private(set) var lastMicLevel: Float = 0

    private let modelContainer: ModelContainer
    private let toolExecutor: VoiceToolExecutor
    private var client: RealtimeClient?
    private var audio: AudioPipeline?
    private var assistantItems: [String: Int] = [:]
    private var pendingConfirmations: [String: PendingConfirmation] = [:]

    // These instructions are intentionally operational. They teach the model
    // when to call local tools and when to ask for confirmation; they do not
    // try to solve audio/VAD behavior, which belongs in the audio pipeline.
    private let systemInstructions = """
# Role & Objective
You are ShipBar, a voice productivity agent. Turn what the user says into the right tool calls quickly and accurately.

# Personality & Tone
- Calm, sharp, builder-minded. Move fast.
- Warm, terse, confident.
- 1–2 short sentences per turn.
- Vary phrasing — don't repeat lines.

# Project routing — CRITICAL
Every task belongs to a project OR Inbox. Inbox is the untriaged fallback and should be rare. Before creating any task, infer the project from context.

Step 1: At the start of any session that involves creating tasks, call list_projects ONCE. Remember the result for the rest of the session.

Step 2: For each task, infer the project:
- Explicit: "add captions to vedit" → vedit. "wire up Sentry to LEARN-X" → LEARN-X.
- Topical: if the task semantically matches a project (e.g., one project is named after a course the user is studying, or a product they're building), route there.
- Carry-over: if the user named a project earlier in this batch ("for vedit, add..."), subsequent items inherit that project unless the user says otherwise.
- Truly ambiguous: ask ONE short question listing the candidates ("vedit, LEARN-X, or Inbox?"). Apply the answer to the rest of the batch.

NEVER silently dump to Inbox. Inbox is only correct when the user said "inbox" explicitly OR when the task is clearly unrelated to any existing project AND you asked and got no match.

# Tools
Read-only — list_today, list_inbox, list_projects: use whenever intent is clear or before routing decisions. No confirmation.

Write — create_task, update_task, mark_done: use when title is captured AND project is decided per the rules above. No confirmation. Act, then summarize.

High-impact — delete_task, handoff_to_agent, open_app: summarize → ask one short confirmation → wait → execute.
- "delete everything" / "wipe all" → delete_task with all=true.
- "delete completed" / "clear done" → delete_task with all=true and completed_only=true.

# Instructions
- If a tool returns no matches or deleted_count=0, say what you searched for and offer to list_today or list_inbox.
- After any batch, give a one-line summary ("Created 3 tasks in vedit").
- For agent handoffs, repeat the target ("Handing off to Claude — confirm?").

# Conversation Flow
1. New session involving task work → list_projects first.
2. Listen for intent.
3. Infer project per task. Ask only when truly ambiguous.
4. For destructive actions: summarize → confirm → execute.
5. After acting, one-line status. Then stop.

# Safety
- Never delete, hand off, or open an app without explicit confirmation.
- If unsure what the user said, ask one short clarifying question.
"""

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.toolExecutor = VoiceToolExecutor(modelContainer: modelContainer)
    }

    var isActive: Bool {
        switch self.state {
        case .idle, .error: false
        default: true
        }
    }

    func start() {
        guard !self.isActive else { return }
        guard let key = KeychainStore.openAIKey() else {
            self.state = .error("Add your OpenAI API key in Settings to use voice.")
            return
        }

        self.entries.removeAll()
        self.state = .connecting

        // Set up audio before opening Realtime. Mic chunks are still gated by
        // RealtimeClient until session.updated, but this lets the panel show
        // whether local capture is alive while the WebSocket connects.
        let client = RealtimeClient(apiKey: key, model: "gpt-realtime-2")
        client.delegate = self
        self.client = client

        let audio = AudioPipeline()
        self.audio = audio

        do {
            try audio.start { [weak self] chunk in
                let level = Self.rmsLevel(pcm16: chunk)
                Task { @MainActor in
                    guard let self else { return }
                    self.lastMicChunkAt = .now
                    self.lastMicLevel = level
                    self.client?.sendAudioChunk(chunk)
                }
            }
        } catch {
            self.state = .error("Audio: \(error.localizedDescription)")
            self.cleanup()
            return
        }

        client.connect()
    }

    func stop() {
        self.cleanup()
        self.state = .idle
    }

    nonisolated private static func rmsLevel(pcm16: Data) -> Float {
        // UI-only mic meter. It should never affect capture, VAD, or send rate.
        let count = pcm16.count / MemoryLayout<Int16>.size
        guard count > 0 else { return 0 }
        var sum: Double = 0
        pcm16.withUnsafeBytes { raw in
            guard let ptr = raw.baseAddress?.assumingMemoryBound(to: Int16.self) else { return }
            for index in 0..<count {
                let value = Double(ptr[index]) / Double(Int16.max)
                sum += value * value
            }
        }
        return Float(sqrt(sum / Double(count)))
    }

    private func cleanup() {
        self.audio?.stop()
        self.audio = nil
        self.client?.disconnect()
        self.client = nil
        self.pendingConfirmations.removeAll()
        self.assistantItems.removeAll()
    }
}

extension VoiceSession: RealtimeClientDelegate {
    func realtimeClientDidConnect() {
        // Configure after socket open. RealtimeClient will not forward mic
        // audio until the server acknowledges with session.updated.
        self.client?.configureSession(
            instructions: self.systemInstructions,
            tools: VoiceTool.allSchemas)
    }

    func realtimeClientDidUpdateSession() {
        self.state = .listening
    }

    func realtimeClientDidDisconnect(error: Error?) {
        if let error {
            self.state = .error(error.localizedDescription)
            return
        }
        // Don't clobber an existing error with idle.
        if case .error = self.state { return }
        self.state = .idle
    }

    func realtimeClient(didReceiveAssistantAudio audioPCM16: Data, itemID: String?) {
        self.audio?.play(pcm16: audioPCM16, itemID: itemID)
    }

    func realtimeClientDidDetectUserSpeech() {
        // Server VAD has detected user speech while audio may be playing. Stop
        // local playback and truncate the assistant item to preserve history.
        guard let interrupted = self.audio?.clearPlaybackForInterruption() else { return }
        self.client?.truncateAssistantAudio(itemID: interrupted.itemID, audioEndMs: interrupted.audioEndMs)
    }

    func realtimeClient(didReceiveAssistantTranscriptDelta text: String, itemID: String) {
        if let index = self.assistantItems[itemID] {
            self.entries[index].text += text
        } else {
            let entry = TranscriptEntry(role: .assistant, text: text, isStreaming: true)
            self.entries.append(entry)
            self.assistantItems[itemID] = self.entries.count - 1
        }
    }

    func realtimeClient(didReceiveAssistantTranscriptDone text: String, itemID: String) {
        if let index = self.assistantItems[itemID] {
            self.entries[index].text = text
            self.entries[index].isStreaming = false
            self.assistantItems[itemID] = nil
        }
    }

    func realtimeClient(didReceiveUserTranscript text: String, itemID: String) {
        self.entries.append(TranscriptEntry(role: .user, text: text))
    }

    func realtimeClient(didRequestToolCall name: String, arguments: [String: Any], callID: String) {
        // This is the only bridge from model intent into local app state.
        // Keep validation and safety rules in VoiceToolExecutor.
        guard let tool = VoiceTool(rawValue: name) else {
            self.client?.submitToolResult(callID: callID, output: "{\"ok\":false,\"error\":\"unknown tool\"}")
            return
        }

        let result = self.toolExecutor.execute(tool: tool, arguments: arguments)
        let summary = self.summary(for: tool, arguments: arguments, result: result)
        self.entries.append(TranscriptEntry(role: .tool, text: summary))
        self.client?.submitToolResult(callID: callID, output: result)
    }

    func realtimeClientDidStartResponse() {
        self.state = .responding
    }

    func realtimeClientDidFinishResponse() {
        self.state = .listening
    }

    func realtimeClient(didReceiveError message: String) {
        self.entries.append(TranscriptEntry(role: .tool, text: "Error: \(message)"))
    }

    private func summary(for tool: VoiceTool, arguments: [String: Any], result: String) -> String {
        switch tool {
        case .createTask:
            let title = arguments["title"] as? String ?? "task"
            let project = arguments["project_name"] as? String ?? "Inbox"
            return "➜ Created '\(title)' in \(project)"
        case .updateTask:
            return "➜ Updated task"
        case .markDone:
            return "➜ Marked done"
        case .deleteTask:
            return "✕ Deleted task"
        case .handoffToAgent:
            let target = arguments["target"] as? String ?? "agent"
            return "➜ Handed off to \(target)"
        case .openApp:
            let app = arguments["app_name"] as? String ?? "app"
            return "➜ Opened \(app)"
        case .listToday, .listInbox, .listProjects:
            return "➜ Read state"
        }
    }
}

private struct PendingConfirmation {
    let tool: VoiceTool
    let arguments: [String: Any]
    let callID: String
}
