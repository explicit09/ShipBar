import Testing

@Suite("Audio pipeline")
struct AudioPipelineTests {
    @Test("voice processing input uses first channel only")
    func voiceProcessingInputUsesFirstChannelOnly() {
        #expect(AudioPipeline.inputChannelMap(forInputChannelCount: 1) == nil)
        #expect(AudioPipeline.inputChannelMap(forInputChannelCount: 3) == [0])
    }
}
