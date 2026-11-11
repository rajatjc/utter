import UtterCore
import Foundation

struct TranscriptionError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Produces the final transcript of one utterance.
@MainActor
protocol Transcriber {
    /// Record a 16 kHz WAV of the utterance (for model-based transcribers).
    var needsRecording: Bool { get }
    /// Run Apple's recognizer during the session (live text, or the result itself).
    var usesLiveRecognizer: Bool { get }
    /// `capture.text` is Apple's live transcript when the recognizer ran.
    func transcribe(_ capture: SpeechEngine.Result, progress: (String) -> Void) async throws -> String
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
struct AppleTranscriber: Transcriber {
    let needsRecording = false
    let usesLiveRecognizer = true

    func transcribe(_ capture: SpeechEngine.Result, progress: (String) -> Void) async throws -> String {
        capture.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Whisper via the local sidecar. Falls back to Apple's transcript (when the
/// live preview ran) if Whisper fails.
struct WhisperTranscriber: Transcriber {
    let needsRecording = true
    var usesLiveRecognizer: Bool { Prefs.showLiveText }

    func transcribe(_ capture: SpeechEngine.Result, progress: (String) -> Void) async throws -> String {
        let fallback = capture.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let wav = capture.wav else { return fallback }
        defer { try? FileManager.default.removeItem(at: wav) }

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
            let words = Prefs.dictionaryWords
            let text = try await sidecar.transcribe(
                wav: wav, language: Prefs.whisperLanguage,
                prompt: words.isEmpty ? nil : words.joined(separator: ", ")
            )
            return text.isEmpty ? fallback : text
        } catch {
            if !fallback.isEmpty { return fallback }
            throw TranscriptionError(message: "Whisper failed: \(error.localizedDescription)")
        }
    }
}
