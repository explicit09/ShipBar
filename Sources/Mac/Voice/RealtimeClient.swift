import Foundation
import os.log

private let rtLog = OSLog(subsystem: "com.tadies.ShipBar", category: "Realtime")

@MainActor
protocol RealtimeClientDelegate: AnyObject {
    func realtimeClientDidConnect()
    func realtimeClientDidUpdateSession()
    func realtimeClientDidDisconnect(error: Error?)
    func realtimeClient(didReceiveAssistantAudio audioPCM16: Data, itemID: String?)
    func realtimeClientDidDetectUserSpeech()
    func realtimeClient(didReceiveAssistantTranscriptDelta text: String, itemID: String)
    func realtimeClient(didReceiveAssistantTranscriptDone text: String, itemID: String)
    func realtimeClient(didReceiveUserTranscript text: String, itemID: String)
    func realtimeClient(didRequestToolCall name: String, arguments: [String: Any], callID: String)
    func realtimeClientDidStartResponse()
    func realtimeClientDidFinishResponse()
    func realtimeClient(didReceiveError message: String)
}

@MainActor
final class RealtimeClient: NSObject {
    // Transport-only boundary. This class should know the Realtime protocol
    // shape, but not SwiftData, panels, or AVAudioEngine details.
    weak var delegate: RealtimeClientDelegate?

    private let apiKey: String
    private let model: String
    private let sessionFactory: (URLSessionWebSocketDelegate) -> RealtimeWebSocketSession
    private var session: RealtimeWebSocketSession?
    private var task: RealtimeWebSocketTask?
    private var isConnected = false
    private var isSessionReady = false
    private var pendingToolArguments: [String: String] = [:]

    init(
        apiKey: String,
        model: String = "gpt-realtime-2",
        sessionFactory: @escaping (URLSessionWebSocketDelegate) -> RealtimeWebSocketSession = { delegate in
            URLSessionRealtimeWebSocketSession(delegate: delegate)
        })
    {
        self.apiKey = apiKey
        self.model = model
        self.sessionFactory = sessionFactory
    }

    func connect() {
        guard self.task == nil else { return }
        let session = self.sessionFactory(self)
        self.session = session

        var components = URLComponents(string: "wss://api.openai.com/v1/realtime")!
        components.queryItems = [URLQueryItem(name: "model", value: self.model)]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(self.apiKey)", forHTTPHeaderField: "Authorization")

        let webSocketTask = session.makeWebSocketTask(with: request)
        self.task = webSocketTask
        webSocketTask.resume()
        self.receiveLoop()
    }

    func disconnect() {
        self.task?.cancel(with: .goingAway, reason: nil)
        self.task = nil
        self.session?.invalidateAndCancel()
        self.session = nil
        self.isConnected = false
        self.isSessionReady = false
        Task { @MainActor in
            self.delegate?.realtimeClientDidDisconnect(error: nil)
        }
    }

    func configureSession(instructions: String, tools: [[String: Any]], voice: String = "marin") {
        // Keep the model in the URL, not in the session body. Current
        // Realtime sessions accept model selection at connection time.
        let payload: [String: Any] = [
            "type": "session.update",
            "session": [
                "type": "realtime",
                "output_modalities": ["audio"],
                "instructions": instructions,
                "audio": [
                    "input": [
                        "format": [
                            "type": "audio/pcm",
                            "rate": 24_000,
                        ],
                        "transcription": [
                            "model": "gpt-4o-transcribe",
                        ],
                        "noise_reduction": [
                            "type": "near_field",
                        ],
                        // Server VAD gives us hands-free wake and barge-in.
                        // Use exact decimal serialization; long binary Double
                        // expansions are rejected by the Realtime API.
                        "turn_detection": [
                            "type": "server_vad",
                            "threshold": NSDecimalNumber(string: "0.5"),
                            "prefix_padding_ms": 300,
                            "silence_duration_ms": 500,
                            "interrupt_response": true,
                            "create_response": true,
                        ],
                    ],
                    "output": [
                        "format": [
                            "type": "audio/pcm",
                            "rate": 24_000,
                        ],
                        "voice": voice,
                    ],
                ],
                "tools": tools,
                "tool_choice": "auto",
            ],
        ]
        self.send(payload)
    }

    func sendAudioChunk(_ pcm16: Data) {
        // Do not stream mic audio until session.updated confirms the server is
        // using our instructions, tools, audio formats, and VAD settings.
        guard self.isSessionReady else { return }
        let base64 = pcm16.base64EncodedString()
        let payload: [String: Any] = [
            "type": "input_audio_buffer.append",
            "audio": base64,
        ]
        self.send(payload)
    }

    func commitAudio() {
        self.send(["type": "input_audio_buffer.commit"])
    }

    func cancelResponse() {
        self.send(["type": "response.cancel"])
    }

    func truncateAssistantAudio(itemID: String, audioEndMs: Int) {
        // WebSocket playback is client-buffered, so OpenAI needs this event to
        // remove assistant audio the user did not actually hear after barge-in.
        let payload: [String: Any] = [
            "type": "conversation.item.truncate",
            "item_id": itemID,
            "content_index": 0,
            "audio_end_ms": audioEndMs,
        ]
        self.send(payload)
    }

    func submitToolResult(callID: String, output: String) {
        // Tool calls are local function tools. After returning the result item,
        // explicitly ask the model to continue from that new conversation state.
        let payload: [String: Any] = [
            "type": "conversation.item.create",
            "item": [
                "type": "function_call_output",
                "call_id": callID,
                "output": output,
            ],
        ]
        self.send(payload)
        self.send(["type": "response.create"])
    }

    private func send(_ payload: [String: Any]) {
        guard let task = self.task, self.isConnected,
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let string = String(data: data, encoding: .utf8)
        else { return }
        task.send(.string(string)) { error in
            if let error {
                Task { @MainActor in
                    self.delegate?.realtimeClient(didReceiveError: "send failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func receiveLoop() {
        guard let task = self.task else { return }
        task.receive { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                switch result {
                case let .failure(error):
                    self.delegate?.realtimeClientDidDisconnect(error: error)
                    self.isConnected = false
                case let .success(message):
                    self.handle(message: message)
                    self.receiveLoop()
                }
            }
        }
    }

    private func handle(message: URLSessionWebSocketTask.Message) {
        switch message {
        case let .string(text):
            self.handleEvent(jsonString: text)
        case let .data(data):
            if let text = String(data: data, encoding: .utf8) {
                self.handleEvent(jsonString: text)
            }
        @unknown default:
            return
        }
    }

    private func handleEvent(jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String
        else { return }

        // Log every event type to the console for debugging.
        if !type.hasPrefix("response.audio") && type != "response.output_audio.delta" {
            os_log("event %{public}@", log: rtLog, type: .info, type as CVarArg)
        }

        switch type {
        case "response.audio.delta", "response.output_audio.delta":
            if let b64 = object["delta"] as? String, let audio = Data(base64Encoded: b64) {
                self.delegate?.realtimeClient(didReceiveAssistantAudio: audio, itemID: object["item_id"] as? String)
            }
        case "response.audio_transcript.delta", "response.output_audio_transcript.delta":
            if let delta = object["delta"] as? String, let itemID = object["item_id"] as? String {
                self.delegate?.realtimeClient(didReceiveAssistantTranscriptDelta: delta, itemID: itemID)
            }
        case "response.audio_transcript.done", "response.output_audio_transcript.done":
            if let text = object["transcript"] as? String, let itemID = object["item_id"] as? String {
                self.delegate?.realtimeClient(didReceiveAssistantTranscriptDone: text, itemID: itemID)
            }
        case "conversation.item.input_audio_transcription.completed":
            if let transcript = object["transcript"] as? String, let itemID = object["item_id"] as? String {
                self.delegate?.realtimeClient(didReceiveUserTranscript: transcript, itemID: itemID)
            }
        case "session.updated":
            self.isSessionReady = true
            self.delegate?.realtimeClientDidUpdateSession()
        case "input_audio_buffer.speech_started":
            // This is the server-side barge-in signal. AudioPipeline stops
            // local playback; RealtimeClient sends the truncate event.
            self.delegate?.realtimeClientDidDetectUserSpeech()
        case "input_audio_buffer.speech_stopped", "input_audio_buffer.committed":
            return
        case "response.function_call_arguments.delta":
            // Function arguments may arrive in deltas before the done event
            // repeats or finalizes the JSON payload.
            if let callID = object["call_id"] as? String, let delta = object["delta"] as? String {
                self.pendingToolArguments[callID, default: ""] += delta
            }
        case "response.function_call_arguments.done":
            if let callID = object["call_id"] as? String,
               let name = object["name"] as? String
            {
                let argsString = object["arguments"] as? String ?? self.pendingToolArguments[callID] ?? "{}"
                self.pendingToolArguments[callID] = nil
                let args = self.parseArguments(argsString)
                self.delegate?.realtimeClient(didRequestToolCall: name, arguments: args, callID: callID)
            }
        case "response.created":
            self.delegate?.realtimeClientDidStartResponse()
        case "response.done":
            self.delegate?.realtimeClientDidFinishResponse()
        case "error":
            let message = (object["error"] as? [String: Any])?["message"] as? String ?? "unknown error"
            os_log("ERROR: %{public}@", log: rtLog, type: .error, jsonString as CVarArg)
            self.delegate?.realtimeClient(didReceiveError: message)
        default:
            return
        }
    }

    private func parseArguments(_ string: String) -> [String: Any] {
        guard let data = string.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return object
    }
}

extension RealtimeClient: URLSessionWebSocketDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?)
    {
        _ = session
        _ = webSocketTask
        _ = `protocol`
        Task { @MainActor in
            self.handleSocketDidOpen()
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?)
    {
        _ = session
        _ = webSocketTask
        _ = closeCode
        _ = reason
        Task { @MainActor in
            guard self.task != nil else { return }
            self.isConnected = false
            self.isSessionReady = false
            self.task = nil
            self.session?.invalidateAndCancel()
            self.session = nil
            self.delegate?.realtimeClientDidDisconnect(error: nil)
        }
    }
}

private extension RealtimeClient {
    func handleSocketDidOpen() {
        guard self.task != nil, !self.isConnected else { return }
        self.isConnected = true
        self.delegate?.realtimeClientDidConnect()
    }
}

#if DEBUG
extension RealtimeClient {
    func simulateSocketDidOpenForTesting() {
        self.handleSocketDidOpen()
    }

    func simulateServerEventForTesting(_ event: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: event),
              let string = String(data: data, encoding: .utf8)
        else { return }
        self.handleEvent(jsonString: string)
    }
}
#endif

protocol RealtimeWebSocketSession: AnyObject {
    func makeWebSocketTask(with request: URLRequest) -> RealtimeWebSocketTask
    func invalidateAndCancel()
}

protocol RealtimeWebSocketTask: AnyObject {
    func resume()
    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)
    func receive(completionHandler: @escaping @Sendable (Result<URLSessionWebSocketTask.Message, Error>) -> Void)
    func send(_ message: URLSessionWebSocketTask.Message, completionHandler: @escaping @Sendable (Error?) -> Void)
}

private final class URLSessionRealtimeWebSocketSession: RealtimeWebSocketSession {
    private let session: URLSession

    init(delegate: URLSessionWebSocketDelegate) {
        self.session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
    }

    func makeWebSocketTask(with request: URLRequest) -> RealtimeWebSocketTask {
        URLSessionRealtimeWebSocketTask(task: self.session.webSocketTask(with: request))
    }

    func invalidateAndCancel() {
        self.session.invalidateAndCancel()
    }
}

private final class URLSessionRealtimeWebSocketTask: RealtimeWebSocketTask {
    private let task: URLSessionWebSocketTask

    init(task: URLSessionWebSocketTask) {
        self.task = task
    }

    func resume() {
        self.task.resume()
    }

    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        self.task.cancel(with: closeCode, reason: reason)
    }

    func receive(completionHandler: @escaping @Sendable (Result<URLSessionWebSocketTask.Message, Error>) -> Void) {
        self.task.receive(completionHandler: completionHandler)
    }

    func send(_ message: URLSessionWebSocketTask.Message, completionHandler: @escaping @Sendable (Error?) -> Void) {
        self.task.send(message, completionHandler: completionHandler)
    }
}
