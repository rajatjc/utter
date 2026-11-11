import UtterCore
import FluidAudio
import Foundation

/// NVIDIA Parakeet TDT 0.6B v3 running on the Neural Engine through FluidAudio.
/// Built into the app: no Python, a one-time ~500 MB model download, and about
/// 0.3 s to transcribe a minute of speech. 25 European languages.
@MainActor
final class ParakeetEngine: ObservableObject {
    static let shared = ParakeetEngine()

    enum Status: Equatable {
        case notInstalled
        case downloading
        case loading
        case ready
        case unloaded   // freed after being idle; reloads on the next dictation
        case failed(String)
    }

    @Published private(set) var status: Status = .notInstalled
    private var manager: AsrManager?
    private var loadTask: Task<Void, Never>?
    private(set) var lastUsed = Date()

    static var modelDirectory: URL {
        WhisperPaths.supportDirectory.appendingPathComponent("parakeet-tdt-0.6b-v3", isDirectory: true) // FluidAudio names it after the model repo
    }

    var isInstalled: Bool { AsrModels.modelsExist(at: Self.modelDirectory, version: .v3) }
    var isReady: Bool { status == .ready }

    init() {
        status = isInstalled ? .unloaded : .notInstalled
    }

    /// Downloads the model if needed, then loads it. Safe to call repeatedly.
    func prepare() {
        guard loadTask == nil, status != .ready else { return }
        status = isInstalled ? .loading : .downloading
        loadTask = Task {
            do {
                let models = try await AsrModels.downloadAndLoad(to: Self.modelDirectory, version: .v3)
                status = .loading
                let manager = AsrManager(config: .default)
                try await manager.loadModels(models)
                self.manager = manager
                lastUsed = Date()
                status = .ready
            } catch {
                status = .failed(error.localizedDescription)
            }
            loadTask = nil
        }
    }

    /// Waits up to `seconds` for a load in progress.
    func waitUntilReady(seconds: Double) async {
        let deadline = Date().addingTimeInterval(seconds)
        while !isReady, Date() < deadline {
            if case .failed = status { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    func transcribe(_ samples: [Int16]) async throws -> String {
        guard let manager else { throw TranscriptionError(message: "Parakeet isn't loaded yet.") }
        lastUsed = Date()
        let floats = samples.map { Float($0) / 32768 }
        var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let result = try await manager.transcribe(floats, decoderState: &state)
        lastUsed = Date()
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Frees the model's memory after `Prefs.idleMinutes` without use.
    func unloadIfIdle(busy: Bool) {
        guard Prefs.freeMemoryWhenIdle, !busy, status == .ready,
              Date().timeIntervalSince(lastUsed) > Prefs.idleMinutes * 60 else { return }
        let old = manager
        manager = nil
        status = .unloaded
        Task { await old?.cleanup() }
    }

    func removeModel() {
        let old = manager
        manager = nil
        Task { await old?.cleanup() }
        try? FileManager.default.removeItem(at: Self.modelDirectory)
        status = .notInstalled
    }
}

/// Records the utterance and transcribes it in one pass on release. Parakeet
/// runs far faster than real time, so streaming chunks wouldn't save anything.
final class ParakeetTranscriber: Transcriber {
    let needsRecording = true
    var usesLiveRecognizer: Bool { Prefs.showLiveText }

    func begin(recording: PCM16Recorder?) {
        Task { @MainActor in ParakeetEngine.shared.prepare() }
    }

    func cancel() {}

    func transcribe(_ capture: SpeechEngine.Result, progress: (String) -> Void) async throws -> String {
        let fallback = capture.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let recorder = capture.recorder else { return fallback }
        let engine = await ParakeetEngine.shared
        if await !engine.isReady {
            progress("Loading Parakeet…")
            await engine.prepare()
            await engine.waitUntilReady(seconds: 30)
        }
        guard await engine.isReady else {
            if !fallback.isEmpty { return fallback }
            throw TranscriptionError(message: "Parakeet isn't ready. Check Settings → AI & dictation.")
        }
        let all = recorder.samples(0..<recorder.count)
        let speechEnd = SpeechDetector.endOfSpeech(all[...])
        guard speechEnd > 0, SpeechDetector.containsSpeech(all[0..<speechEnd]) else { return fallback }
        progress("Transcribing…")
        // Parakeet needs at least a second of audio; pad short clips with silence.
        var samples = Array(all[0..<speechEnd])
        if samples.count < 16_000 { samples += [Int16](repeating: 0, count: 16_000 - samples.count) }
        let text = RepetitionFilter.collapse(try await engine.transcribe(samples))
        return text.isEmpty ? fallback : text
    }
}
