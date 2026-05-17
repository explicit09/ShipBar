import Foundation
import Testing

@Suite("Realtime client")
@MainActor
struct RealtimeClientTests {
    @Test("connect waits for WebSocket open before sending session updates")
    func connectWaitsForWebSocketOpenBeforeSendingSessionUpdates() {
        let socket = FakeRealtimeWebSocketTask()
        let session = FakeRealtimeWebSocketSession(socket: socket)
        let delegate = RealtimeDelegateSpy()
        let client = RealtimeClient(
            apiKey: "test-key",
            model: "gpt-realtime-2",
            sessionFactory: { _ in session })
        client.delegate = delegate

        client.connect()
        client.configureSession(instructions: "listen", tools: [])

        #expect(socket.didResume)
        #expect(delegate.didConnectCount == 0)
        #expect(socket.sentMessages.isEmpty)

        client.simulateSocketDidOpenForTesting()
        client.configureSession(instructions: "listen", tools: [])
        client.sendAudioChunk(Data([0, 1, 2, 3]))

        #expect(delegate.didConnectCount == 1)
        #expect(socket.sentMessages.count == 1)
        let sessionUpdateText = socket.sentTextMessages.first
        #expect(sessionUpdateText?.contains("\"type\":\"session.update\"") == true)
        #expect(sessionUpdateText?.contains("\"threshold\":0.5") == true)
        #expect(sessionUpdateText?.contains("\"noise_reduction\":{\"type\":\"near_field\"}") == true)
        #expect(sessionUpdateText?.contains("0.29999999999999999") == false)
        let updateSession = socket.firstSentSessionUpdate()
        #expect(updateSession?["model"] == nil)
        #expect(session.requests.first?.url?.query?.contains("model=gpt-realtime-2") == true)
        let turnDetection = updateSession?.inputTurnDetection()
        #expect(turnDetection?["type"] as? String == "server_vad")
        #expect(turnDetection?["threshold"] as? Double == 0.5)
        #expect(turnDetection?["silence_duration_ms"] as? Int == 500)

        client.simulateServerEventForTesting(["type": "session.updated"])
        client.sendAudioChunk(Data([0, 1, 2, 3]))

        #expect(delegate.didUpdateSessionCount == 1)
        #expect(socket.sentMessages.count == 2)
        #expect(socket.sentTextMessages.last?.contains("\"type\":\"input_audio_buffer.append\"") == true)
    }

    @Test("speech started interrupts local playback and truncate sends playback position")
    func speechStartedInterruptsPlaybackAndTruncateSendsPlaybackPosition() {
        let socket = FakeRealtimeWebSocketTask()
        let session = FakeRealtimeWebSocketSession(socket: socket)
        let delegate = RealtimeDelegateSpy()
        let client = RealtimeClient(
            apiKey: "test-key",
            model: "gpt-realtime-2",
            sessionFactory: { _ in session })
        client.delegate = delegate

        client.connect()
        client.simulateSocketDidOpenForTesting()
        client.simulateServerEventForTesting([
            "type": "response.output_audio.delta",
            "item_id": "assistant-item",
            "delta": Data([1, 2, 3, 4]).base64EncodedString(),
        ])
        client.simulateServerEventForTesting(["type": "input_audio_buffer.speech_started"])
        client.truncateAssistantAudio(itemID: "assistant-item", audioEndMs: 1500)

        #expect(delegate.receivedAssistantAudioItemID == "assistant-item")
        #expect(delegate.didDetectUserSpeechCount == 1)
        #expect(socket.sentTextMessages.last?.contains("\"type\":\"conversation.item.truncate\"") == true)
        #expect(socket.sentTextMessages.last?.contains("\"item_id\":\"assistant-item\"") == true)
        #expect(socket.sentTextMessages.last?.contains("\"audio_end_ms\":1500") == true)
    }
}

private extension Dictionary where Key == String, Value == Any {
    func inputTurnDetection() -> [String: Any]? {
        guard let audio = self["audio"] as? [String: Any],
              let input = audio["input"] as? [String: Any]
        else { return nil }
        return input["turn_detection"] as? [String: Any]
    }
}

private final class FakeRealtimeWebSocketSession: RealtimeWebSocketSession {
    let socket: FakeRealtimeWebSocketTask
    private(set) var didInvalidate = false
    private(set) var requests: [URLRequest] = []

    init(socket: FakeRealtimeWebSocketTask) {
        self.socket = socket
    }

    func makeWebSocketTask(with request: URLRequest) -> RealtimeWebSocketTask {
        self.requests.append(request)
        return self.socket
    }

    func invalidateAndCancel() {
        self.didInvalidate = true
    }
}

private final class FakeRealtimeWebSocketTask: RealtimeWebSocketTask {
    private(set) var didResume = false
    private(set) var didCancel = false
    private(set) var sentMessages: [URLSessionWebSocketTask.Message] = []

    var sentTextMessages: [String] {
        self.sentMessages.compactMap { message in
            if case let .string(text) = message { return text }
            return nil
        }
    }

    func firstSentSessionUpdate() -> [String: Any]? {
        guard let text = self.sentTextMessages.first,
              let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object["session"] as? [String: Any]
    }

    func resume() {
        self.didResume = true
    }

    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        _ = closeCode
        _ = reason
        self.didCancel = true
    }

    func receive(completionHandler: @escaping @Sendable (Result<URLSessionWebSocketTask.Message, Error>) -> Void) {
        _ = completionHandler
    }

    func send(_ message: URLSessionWebSocketTask.Message, completionHandler: @escaping @Sendable (Error?) -> Void) {
        self.sentMessages.append(message)
        completionHandler(nil)
    }
}

@MainActor
private final class RealtimeDelegateSpy: RealtimeClientDelegate {
    private(set) var didConnectCount = 0
    private(set) var didUpdateSessionCount = 0
    private(set) var didDetectUserSpeechCount = 0
    private(set) var receivedAssistantAudioItemID: String?

    func realtimeClientDidConnect() {
        self.didConnectCount += 1
    }

    func realtimeClientDidUpdateSession() {
        self.didUpdateSessionCount += 1
    }

    func realtimeClientDidDisconnect(error: Error?) {
        _ = error
    }

    func realtimeClient(didReceiveAssistantAudio audioPCM16: Data, itemID: String?) {
        _ = audioPCM16
        self.receivedAssistantAudioItemID = itemID
    }

    func realtimeClientDidDetectUserSpeech() {
        self.didDetectUserSpeechCount += 1
    }

    func realtimeClient(didReceiveAssistantTranscriptDelta text: String, itemID: String) {
        _ = text
        _ = itemID
    }

    func realtimeClient(didReceiveAssistantTranscriptDone text: String, itemID: String) {
        _ = text
        _ = itemID
    }

    func realtimeClient(didReceiveUserTranscript text: String, itemID: String) {
        _ = text
        _ = itemID
    }

    func realtimeClient(didRequestToolCall name: String, arguments: [String: Any], callID: String) {
        _ = name
        _ = arguments
        _ = callID
    }

    func realtimeClientDidStartResponse() {}

    func realtimeClientDidFinishResponse() {}

    func realtimeClient(didReceiveError message: String) {
        _ = message
    }
}
