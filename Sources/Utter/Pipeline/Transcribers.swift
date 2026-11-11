import UtterCore
import Foundation

struct TranscriptionError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Produces the final transcript of one utterance. One instance per session.
@MainActor
protocol Transcriber: AnyObject {
    /// Record 16 kHz audio of the utterance (for model-based transcribers).
    var needsRecording: Bool { get }
    /// Run Apple's recognizer during the session (live text, or the result itself).
    var usesLiveRecognizer: Bool { get }
    /// Recording has started; streaming transcribers can begin work.
    func begin(recording: PCM16Recorder?)
    /// `capture.text` is Apple's live transcript when the recognizer ran.
    func transcribe(_ capture: SpeechEngine.Result, progress: (String) -> Void) async throws -> String
    /// The session was cancelled.
    func cancel()
}

@MainActor
enum Transcribers {
    /// Whisper when it's selected and hasn't failed, else Apple's recognizer.
    static func current() -> Transcriber {
        if Prefs.speechEngine == .whisper {
            switch WhisperSidecar.shared.status {
            case .failed, .installing: break
            default: return WhisperTranscriber()
            }
        }
        return AppleTranscriber()
    }
}

/// Apple's on-device recognizer: the live transcript is the result.
final class AppleTranscriber: Transcriber {
    let needsRecording = false
    let usesLiveRecognizer = true

    func begin(recording: PCM16Recorder?) {}
    func cancel() {}

    func transcribe(_ capture: SpeechEngine.Result, progress: (String) -> Void) async throws -> String {
        capture.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Whisper via the local sidecar, streamed: while the user talks, every chunk
/// that ends at a natural pause (see `PauseChunker`) is transcribed in the
/// background, so on release only the last few seconds are left. Each chunk
/// gets the previous chunk's text as context, so the pieces read as one.
///
/// Measured on a 70 s dictation: 0.6 s after release instead of 2.6 s, with
/// the same text as transcribing it all at once.
final class WhisperTranscriber: Transcriber {
    let needsRecording = true
    var usesLiveRecognizer: Bool { Prefs.showLiveText }

    private var recorder: PCM16Recorder?
    private var timer: Timer?
    /// Start of the audio not yet sent to Whisper (in samples).
    private var sent = 0
    /// Chunk transcriptions run one after another; each awaits the previous.
    private var chain: Task<[String], Error>?
    private var cancelled = false

    func begin(recording: PCM16Recorder?) {
        recorder = recording
        guard recording != nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func cancel() {
        cancelled = true
        timer?.invalidate()
        timer = nil
        chain?.cancel()
        chain = nil
    }

    /// While recording: if the unsent audio has reached a pause, send it.
    private func tick() {
        guard let recorder, WhisperSidecar.shared.isReady, !cancelled else { return }
        let end = recorder.count
        guard end - sent >= PCM16Recorder.sampleRate * 5 else { return } // cheap early exit
        let pending = recorder.samples(sent..<end)
        guard let cut = PauseChunker.cut(pending[...]) else { return }
        enqueue(Array(pending[0..<cut]))
        sent += cut
    }

    private func enqueue(_ samples: [Int16]) {
        let previous = chain
        chain = Task { @MainActor in
            var texts = try await previous?.value ?? []
            try Task.checkCancellation()
            texts.append(try await Self.transcribe(samples, context: texts.last))
            return texts
        }
    }

    func transcribe(_ capture: SpeechEngine.Result, progress: (String) -> Void) async throws -> String {
        timer?.invalidate()
        timer = nil
        let fallback = capture.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let recorder = capture.recorder ?? recorder else { return fallback }

        let sidecar = WhisperSidecar.shared
        // Whisper may still be loading right after launch: give it a few seconds.
        if !sidecar.isReady {
            progress("Starting Whisper…")
            for _ in 0..<40 where !sidecar.isReady {
                if case .failed = sidecar.status { break }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        guard sidecar.isReady else {
            if !fallback.isEmpty { return fallback }
            throw TranscriptionError(message: "Whisper isn't running. Check Settings → AI & dictation.")
        }
        progress("Transcribing…")
        do {
            // Finish the chunks already in flight, then the remainder.
            var texts = try await chain?.value ?? []
            let rest = recorder.samples(sent..<recorder.count)
            if rest.count >= PCM16Recorder.sampleRate / 3 {
                texts.append(try await Self.transcribe(rest, context: texts.last))
            }
            let text = texts.filter { !$0.isEmpty }.joined(separator: " ")
            return text.isEmpty ? fallback : text
        } catch {
            // A chunk failed: try the whole recording once before giving up.
            if let text = try? await Self.transcribe(recorder.samples(0..<recorder.count), context: nil), !text.isEmpty {
                return text
            }
            if !fallback.isEmpty { return fallback }
            throw TranscriptionError(message: "Whisper failed: \(error.localizedDescription)")
        }
    }

    /// One request to the sidecar. The prompt carries the personal dictionary
    /// (spellings) and the end of the previous chunk (continuity).
    private static func transcribe(_ samples: [Int16], context: String?) async throws -> String {
        let wav = try PCM16Recorder.writeWAV(samples)
        defer { try? FileManager.default.removeItem(at: wav) }
        var prompt = Prefs.dictionaryWords.joined(separator: ", ")
        if let context, !context.isEmpty {
            prompt += (prompt.isEmpty ? "" : ". ") + String(context.suffix(200))
        }
        return try await WhisperSidecar.shared.transcribe(
            wav: wav, language: Prefs.whisperLanguage, prompt: prompt.isEmpty ? nil : prompt
        )
    }
}
