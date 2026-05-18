@preconcurrency import AVFoundation
import Foundation

final class AudioPipeline: @unchecked Sendable {
    // OpenAI WebSocket transport gives us raw PCM, so this object owns both
    // sides of the full-duplex audio loop: mic capture and assistant playback.
    private let targetSampleRate: Double = 24_000
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let targetFormat: AVAudioFormat
    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private var playbackConverter: AVAudioConverter?
    private var playbackFormat: AVAudioFormat?
    private var isStarted = false
    private var currentPlaybackItemID: String?
    private var currentPlaybackStartedAt: Date?
    private var currentPlaybackDuration: TimeInterval = 0
    private var onCapture: (@Sendable (Data) -> Void)?
    #if os(iOS)
    private var didConfigureAudioSession = false
    #endif

    init() {
        self.targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24_000, channels: 1, interleaved: true)!
    }

    func start(onCapture: @escaping @Sendable (Data) -> Void) throws {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard !self.isStarted else { return }
        self.onCapture = onCapture

        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)
        self.didConfigureAudioSession = true
        #endif

        let input = self.engine.inputNode
        let output = self.engine.outputNode

        // Enable Apple's acoustic echo cancellation before reading formats.
        // Voice processing can change channel layout and sample format, so the
        // converter/tap must be configured from the post-voice-processing nodes.
        try input.setVoiceProcessingEnabled(true)
        try output.setVoiceProcessingEnabled(true)

        let inputFormat = input.outputFormat(forBus: 0)
        let outputFormat = output.inputFormat(forBus: 0)
        self.playbackFormat = outputFormat
        self.playbackConverter = AVAudioConverter(from: self.targetFormat, to: outputFormat)
        self.converter = AVAudioConverter(from: inputFormat, to: self.targetFormat)
        if let channelMap = Self.inputChannelMap(forInputChannelCount: Int(inputFormat.channelCount)) {
            self.converter?.channelMap = channelMap
        }

        // Player feeds the hardware output directly. Skipping the main mixer
        // keeps the output in the same I/O graph used for echo cancellation.
        self.engine.attach(self.playerNode)
        self.engine.connect(self.playerNode, to: output, format: outputFormat)

        let bufferSize: AVAudioFrameCount = 1024
        input.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            self?.process(captureBuffer: buffer)
        }

        do {
            try self.engine.start()
        } catch {
            // Roll back so a retry starts clean.
            input.removeTap(onBus: 0)
            self.engine.detach(self.playerNode)
            #if os(iOS)
            if self.didConfigureAudioSession {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                self.didConfigureAudioSession = false
            }
            #endif
            throw error
        }

        self.playerNode.play()
        self.isStarted = true
    }

    func stop() {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard self.isStarted else { return }
        self.engine.inputNode.removeTap(onBus: 0)
        self.playerNode.stop()
        self.engine.stop()
        self.isStarted = false
        self.resetPlaybackTracking()
        self.playbackConverter = nil
        self.playbackFormat = nil
        self.converter = nil
        self.onCapture = nil
        #if os(iOS)
        if self.didConfigureAudioSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            self.didConfigureAudioSession = false
        }
        #endif
    }

    func play(pcm16: Data, itemID: String?) {
        self.lock.lock()
        let started = self.isStarted
        let playbackFormat = self.playbackFormat
        let playbackConverter = self.playbackConverter
        self.lock.unlock()
        guard started, !pcm16.isEmpty, let playbackFormat, let playbackConverter else { return }

        // Realtime output is 24 kHz PCM16 mono. Keep one output converter alive
        // across chunks so the resampler does not restart its filter state on
        // every delta, which can sound like small repeated clicks or syllables.
        let inFrames = AVAudioFrameCount(pcm16.count / MemoryLayout<Int16>.size)
        guard inFrames > 0,
              let int16Buffer = AVAudioPCMBuffer(pcmFormat: self.targetFormat, frameCapacity: inFrames)
        else { return }
        int16Buffer.frameLength = inFrames
        pcm16.withUnsafeBytes { raw in
            guard let src = raw.baseAddress?.assumingMemoryBound(to: Int16.self),
                  let dst = int16Buffer.int16ChannelData?[0]
            else { return }
            memcpy(dst, src, pcm16.count)
        }

        let ratio = playbackFormat.sampleRate / self.targetFormat.sampleRate
        let outCapacity = AVAudioFrameCount(Double(inFrames) * ratio) + 64
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: outCapacity) else { return }

        let inputState = AudioConverterInputState()
        var error: NSError?
        playbackConverter.convert(to: outBuffer, error: &error) { _, status in
            if inputState.consumed { status.pointee = .noDataNow; return nil }
            inputState.consumed = true
            status.pointee = .haveData
            return int16Buffer
        }
        if error != nil { return }

        self.lock.lock()
        // Track the assistant item and approximate played duration so a later
        // barge-in can truncate conversation history at what the user heard.
        if self.currentPlaybackItemID != itemID {
            self.currentPlaybackItemID = itemID
            self.currentPlaybackStartedAt = Date()
            self.currentPlaybackDuration = 0
        } else if self.currentPlaybackStartedAt == nil {
            self.currentPlaybackStartedAt = Date()
        }
        self.currentPlaybackDuration += Double(inFrames) / self.targetSampleRate
        self.lock.unlock()

        self.playerNode.scheduleBuffer(outBuffer, completionHandler: nil)
    }

    func clearPlaybackForInterruption() -> InterruptedPlayback? {
        self.lock.lock()
        defer { self.lock.unlock() }
        // WebSocket clients own output buffering. On server VAD speech_start,
        // stop any queued assistant audio locally before telling Realtime where
        // the assistant response should be truncated.
        let interrupted = self.interruptedPlaybackLocked()
        self.playerNode.stop()
        self.playbackConverter?.reset()
        self.playerNode.play()
        self.resetPlaybackTracking()
        return interrupted
    }

    private func process(captureBuffer buffer: AVAudioPCMBuffer) {
        self.lock.lock()
        let converter = self.converter
        let callback = self.onCapture
        self.lock.unlock()
        guard let converter, let callback else { return }

        let inputFrameCount = buffer.frameLength
        guard inputFrameCount > 0 else { return }

        let ratio = self.targetFormat.sampleRate / buffer.format.sampleRate
        let estimatedFrames = AVAudioFrameCount(Double(inputFrameCount) * ratio) + 64
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: self.targetFormat, frameCapacity: estimatedFrames) else { return }

        let inputState = AudioConverterInputState()
        var error: NSError?
        converter.convert(to: outputBuffer, error: &error) { _, statusPointer in
            if inputState.consumed {
                statusPointer.pointee = .noDataNow
                return nil
            }
            inputState.consumed = true
            statusPointer.pointee = .haveData
            return buffer
        }

        if error != nil { return }
        let outFrameCount = Int(outputBuffer.frameLength)
        guard outFrameCount > 0, let channelData = outputBuffer.int16ChannelData?[0] else { return }
        // This is the only audio sent upstream: echo-cancelled, mono, 24 kHz
        // PCM16. Server VAD and transcription both depend on this stream.
        let byteCount = outFrameCount * MemoryLayout<Int16>.size
        let data = Data(bytes: channelData, count: byteCount)
        callback(data)
    }

    private func interruptedPlaybackLocked() -> InterruptedPlayback? {
        guard let itemID = self.currentPlaybackItemID,
              let startedAt = self.currentPlaybackStartedAt
        else { return nil }
        let played = min(max(Date().timeIntervalSince(startedAt), 0), self.currentPlaybackDuration)
        return InterruptedPlayback(itemID: itemID, audioEndMs: max(0, Int((played * 1000).rounded())))
    }

    private func resetPlaybackTracking() {
        self.currentPlaybackItemID = nil
        self.currentPlaybackStartedAt = nil
        self.currentPlaybackDuration = 0
    }

    static func inputChannelMap(forInputChannelCount channelCount: Int) -> [NSNumber]? {
        // Voice processing can expose auxiliary channels for AEC internals.
        // OpenAI expects mono speech input, so preserve only the first channel.
        channelCount > 1 ? [0] : nil
    }
}

struct InterruptedPlayback: Equatable {
    let itemID: String
    let audioEndMs: Int
}

private final class AudioConverterInputState: @unchecked Sendable {
    var consumed = false
}
