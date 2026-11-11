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
#endif
