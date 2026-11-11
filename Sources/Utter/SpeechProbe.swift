import UtterCore
import AVFoundation
import Speech

#if DEBUG
/// Developer aid: `Utter.app/Contents/MacOS/Utter --probe-speech <audio file>`
/// plays a file into Apple's recognizer in real time and prints every raw
/// callback plus the stitched transcript, then exits. Used to check how the
/// recognizer behaves across pauses. Not used in normal launches.
enum SpeechProbe {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--probe-speech"), i + 1 < args.count else { return false }
        let url = URL(fileURLWithPath: args[i + 1])
        setvbuf(stdout, nil, _IONBF, 0) // print immediately, even through a pipe
        print("probing \(url.path)")
        Task { await run(url) }
        return true
    }

    private static func run(_ url: URL) async {
        let status = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
        guard status == .authorized else { print("speech not authorized: \(status.rawValue)"); exit(1) }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), recognizer.isAvailable else {
            print("recognizer unavailable"); exit(1)
        }
        print("on-device supported: \(recognizer.supportsOnDeviceRecognition)")
        let file: AVAudioFile
        do { file = try AVAudioFile(forReading: url) } catch { print("can't read \(url.path): \(error)"); exit(1) }

        let started = Date()
        func stamp() -> String { String(format: "%5.2fs", Date().timeIntervalSince(started)) }
        let stream = RecognitionStream(recognizer: recognizer, contextualStrings: []) { text in
            print("\(stamp()) stitched: \(text)")
        }
        stream.onRaw = { text, isFinal, error in
            if let error { print("\(stamp()) raw error: \(error.localizedDescription)") }
            else { print("\(stamp()) raw\(isFinal ? " FINAL" : ""): \(text)") }
        }

        // Feed 100 ms buffers at real-time pace so silence detection behaves as live.
        let format = file.processingFormat
        let chunk = AVAudioFrameCount(format.sampleRate / 10)
        while file.framePosition < file.length {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else { break }
            do { try file.read(into: buffer, frameCount: chunk) } catch { break }
            if buffer.frameLength == 0 { break }
            stream.append(buffer)
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        // Trailing silence, as when the user holds the key a moment before releasing.
        if let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) {
            silence.frameLength = chunk
            for _ in 0..<5 { stream.append(silence); try? await Task.sleep(nanoseconds: 100_000_000) }
        }
        let final = await stream.finish()
        print("FINAL TEXT: \(final)")
        exit(0)
    }
}

/// Developer aid: `Utter --probe-whisper-stream <16 kHz mono WAV>` plays a
/// recording into the streaming Whisper transcriber at real-time pace, as if
/// someone were talking, then compares it with transcribing the whole file at
/// once. Prints the wait after "release" for both, and both texts.
@MainActor
enum StreamProbe {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--probe-whisper-stream"), i + 1 < args.count else { return false }
        setvbuf(stdout, nil, _IONBF, 0)
        let url = URL(fileURLWithPath: args[i + 1])
        Task { @MainActor in await run(url) }
        return true
    }

    private static func run(_ url: URL) async {
        let sidecar = WhisperSidecar.shared
        sidecar.ensureRunning()
        while !sidecar.isReady {
            if case .failed(let reason) = sidecar.status { print("Whisper failed: \(reason)"); exit(1) }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        guard let file = try? AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: true),
              file.processingFormat.sampleRate == 16000, file.processingFormat.channelCount == 1,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil, let data = buffer.int16ChannelData
        else { print("need a 16 kHz mono WAV"); exit(1) }
        let samples = Array(UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength)))
        let seconds = Double(samples.count) / 16000
        print(String(format: "audio: %.1f s", seconds))

        var started = Date()
        let whole = (try? await sidecar.transcribe(wav: url, language: Prefs.whisperLanguage, prompt: nil)) ?? "(failed)"
        let wholeWait = Date().timeIntervalSince(started)

        let recorder = PCM16Recorder()
        let transcriber = WhisperTranscriber()
        transcriber.begin(recording: recorder)
        var index = 0
        while index < samples.count { // 100 ms of audio every 100 ms
            let next = min(index + 1600, samples.count)
            recorder.append(samples[index..<next])
            index = next
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        started = Date()
        let streamed = (try? await transcriber.transcribe(SpeechEngine.Result(text: "", recorder: recorder)) { _ in }) ?? "(failed)"
        let streamWait = Date().timeIntervalSince(started)

        print(String(format: "all at once: %.2f s after release", wholeWait))
        print(String(format: "streamed   : %.2f s after release", streamWait))
        print("ALL: \(whole)")
        print("STR: \(streamed)")
        exit(0)
    }
}

/// Developer aid: `Utter --probe-parakeet <16 kHz mono WAV>` downloads and
/// loads Parakeet if needed, then transcribes the file the way a dictation is
/// transcribed on release, printing the load time, the wait and the text.
@MainActor
enum ParakeetProbe {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--probe-parakeet"), i + 1 < args.count else { return false }
        setvbuf(stdout, nil, _IONBF, 0)
        let url = URL(fileURLWithPath: args[i + 1])
        Task { @MainActor in await run(url) }
        return true
    }

    private static func run(_ url: URL) async {
        let engine = ParakeetEngine.shared
        var started = Date()
        engine.prepare()
        while !engine.isReady {
            if case .failed(let reason) = engine.status { print("Parakeet failed: \(reason)"); exit(1) }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        print(String(format: "download + load: %.1f s", Date().timeIntervalSince(started)))
        guard let file = try? AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: true),
              file.processingFormat.sampleRate == 16000, file.processingFormat.channelCount == 1,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil, let data = buffer.int16ChannelData
        else { print("need a 16 kHz mono WAV"); exit(1) }
        let samples = Array(UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength)))
        print(String(format: "audio: %.1f s", Double(samples.count) / 16000))
        let recorder = PCM16Recorder()
        recorder.append(samples[...])
        for run in 1...2 { // the first call warms up the Neural Engine
            started = Date()
            let text = (try? await ParakeetTranscriber().transcribe(SpeechEngine.Result(text: "", recorder: recorder)) { _ in }) ?? "(failed)"
            print(String(format: "run %d: %.2f s after release", run, Date().timeIntervalSince(started)))
            if run == 2 { print("TEXT: \(text)") }
        }
        exit(0)
    }
}
#endif
