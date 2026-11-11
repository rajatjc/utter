import UtterCore
import AVFoundation
import Speech

enum SpeechError: LocalizedError {
    case notAuthorized
    case unavailable

    var errorDescription: String? {
        switch self {
        case .notAuthorized: "Speech recognition isn't allowed. Enable it in System Settings → Privacy & Security."
        case .unavailable: "Speech recognition is unavailable. Check that Siri & Dictation is turned on in System Settings."
        }
    }
}

/// Streams microphone audio into Apple's speech recognizer (on-device when
/// supported) and, optionally, records a 16 kHz WAV for Whisper. Deliberately
/// not main-actor isolated: the audio tap and recognizer callbacks run on
/// background threads. Every callback it gives you is delivered on the main queue.
final class SpeechEngine: @unchecked Sendable { // state is only touched on the main queue
    struct Result {
        /// Apple's transcript ("" if the recognizer wasn't available).
        var text: String
        /// The 16 kHz recording, when recording was requested.
        var recorder: PCM16Recorder?
    }

    private let engine = AVAudioEngine()
    private var stream: RecognitionStream?
    private var recorder: PCM16Recorder?

    /// The recording in progress, so a transcriber can start on it before the user stops.
    var liveRecorder: PCM16Recorder? { recorder }

    /// - useRecognizer: run Apple's recognizer (for the final text, or just a live preview).
    /// - requireRecognizer: fail if it can't run (when it's the only recognizer).
    /// - record: keep a WAV of the utterance for Whisper.
    func start(
        locale: Locale,
        contextualStrings: [String],
        useRecognizer: Bool,
        requireRecognizer: Bool,
        record: Bool,
        onPartial: @escaping (String) -> Void,
        onLevel: @escaping (Float) -> Void
    ) throws {
        cancel()

        var recognizer: SFSpeechRecognizer?
        if useRecognizer, SFSpeechRecognizer.authorizationStatus() == .authorized,
           let r = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(), r.isAvailable {
            recognizer = r
        }
        if recognizer == nil, requireRecognizer {
            throw SFSpeechRecognizer.authorizationStatus() == .authorized ? SpeechError.unavailable : SpeechError.notAuthorized
        }

        let stream = recognizer.map {
            RecognitionStream(recognizer: $0, contextualStrings: contextualStrings, onUpdate: onPartial)
        }
        self.stream = stream

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let recorder = record ? PCM16Recorder(input: format) : nil
        self.recorder = recorder
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format,
                         block: Self.tapBlock(stream: stream, recorder: recorder, onLevel: onLevel))
        engine.prepare()
        try engine.start()
    }

    /// Stops recording and waits briefly for the recognizer's final words.
    func stop() async -> Result {
        stopAudio()
        let recorder = self.recorder
        self.recorder = nil
        let text = await stream?.finish() ?? ""
        stream = nil
        return Result(text: text, recorder: recorder)
    }

    func cancel() {
        stopAudio()
        stream?.cancel()
        stream = nil
        recorder = nil
    }

    private func stopAudio() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
    }

    /// Built in a static context so the closure isn't tied to any actor; it runs on the audio thread.
    private static func tapBlock(
        stream: RecognitionStream?,
        recorder: PCM16Recorder?,
        onLevel: @escaping (Float) -> Void
    ) -> AVAudioNodeTapBlock {
        var lastLevelUpdate = Date.distantPast
        return { buffer, _ in
            stream?.append(buffer)
            recorder?.append(buffer)
            let now = Date()
            guard now.timeIntervalSince(lastLevelUpdate) > 0.05,
                  let channel = buffer.floatChannelData?[0]
            else { return }
            lastLevelUpdate = now
            let n = Int(buffer.frameLength)
            guard n > 0 else { return }
            var sum: Float = 0
            for i in 0..<n { sum += channel[i] * channel[i] }
            let rms = sqrt(sum / Float(n))
            // Map roughly -50 dB...0 dB to 0...1.
            let db = 20 * log10(max(rms, 0.000_01))
            let level = max(0, min(1, (db + 50) / 50))
            DispatchQueue.main.async { onLevel(level) }
        }
    }
}

/// Converts microphone buffers to 16 kHz mono 16-bit PCM in memory (the format
/// Whisper expects). Safe to read from the main thread while the audio thread
/// keeps appending, so chunks can be transcribed during recording.
final class PCM16Recorder: @unchecked Sendable {
    static let sampleRate = 16000

    private let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
    private let converter: AVAudioConverter?
    private let lock = NSLock()
    private var pcm: [Int16] = []

    init(input: AVAudioFormat) {
        converter = AVAudioConverter(from: input, to: target)
        pcm.reserveCapacity(16000 * 60)
    }

    /// For feeding already-converted samples (diagnostics).
    init() {
        converter = nil
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, out.frameLength > 0, let samples = out.int16ChannelData else { return }
        append(UnsafeBufferPointer(start: samples[0], count: Int(out.frameLength)))
    }

    func append<S: Sequence>(_ samples: S) where S.Element == Int16 {
        lock.lock()
        let start = pcm.count
        pcm.append(contentsOf: samples)
        if start < silenceUntil {
            for i in start..<min(silenceUntil, pcm.count) { pcm[i] = 0 }
        }
        lock.unlock()
    }

    private var silenceUntil = 0

    /// Replaces the first `seconds` of the recording with silence (the start
    /// chime plays then; it must not be transcribed).
    func silenceLeading(seconds: Double) {
        lock.lock()
        silenceUntil = Int(seconds * Double(Self.sampleRate))
        for i in 0..<min(silenceUntil, pcm.count) { pcm[i] = 0 }
        lock.unlock()
    }

    /// Samples recorded so far.
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return pcm.count
    }

    /// A copy of the samples in `range` (clamped to what's been recorded).
    func samples(_ range: Range<Int>) -> [Int16] {
        lock.lock()
        defer { lock.unlock() }
        let lower = max(0, min(range.lowerBound, pcm.count))
        let upper = max(lower, min(range.upperBound, pcm.count))
        return Array(pcm[lower..<upper])
    }

    func writeWAV() throws -> URL {
        try Self.writeWAV(samples(0..<Int.max))
    }

    /// Writes 16 kHz mono 16-bit PCM to a temporary WAV file.
    static func writeWAV(_ samples: [Int16]) throws -> URL {
        let body = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        var wav = Data(capacity: body.count + 44)
        func put<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { wav.append(contentsOf: $0) }
        }
        wav.append(contentsOf: Array("RIFF".utf8)); put(UInt32(36 + body.count))
        wav.append(contentsOf: Array("WAVE".utf8))
        wav.append(contentsOf: Array("fmt ".utf8)); put(UInt32(16))
        put(UInt16(1)); put(UInt16(1)); put(UInt32(16000)); put(UInt32(32000)); put(UInt16(2)); put(UInt16(16))
        wav.append(contentsOf: Array("data".utf8)); put(UInt32(body.count))
        wav.append(body)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("utter-\(UUID().uuidString).wav")
        try wav.write(to: url)
        return url
    }
}
