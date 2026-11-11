import UtterCore
import AVFoundation
import Speech

/// Keeps Apple's recognizer going across pauses.
///
/// After a couple of seconds of silence the on-device recognizer either finishes
/// its task or restarts its transcription from scratch, so everything said before
/// the pause would vanish. This commits finished segments, starts a new task on
/// the same audio stream, and reports the stitched text.
final class RecognitionStream: @unchecked Sendable {
    private let recognizer: SFSpeechRecognizer
    private let contextualStrings: [String]
    private let onUpdate: (String) -> Void
    /// Debug hook: every raw recognizer callback (text, isFinal, error).
    var onRaw: ((String, Bool, Error?) -> Void)?

    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var generation = 0
    private var restarts = 0

    private var stitcher = SegmentStitcher()
    private var ended = false
    private var waiter: CheckedContinuation<String, Never>?

    /// Callbacks arrive on the main queue.
    init(recognizer: SFSpeechRecognizer, contextualStrings: [String], onUpdate: @escaping (String) -> Void) {
        self.recognizer = recognizer
        self.contextualStrings = contextualStrings
        self.onUpdate = onUpdate
        startTask()
    }

    var text: String { stitcher.text }

    /// Safe to call from the audio thread.
    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let request = self.request
        lock.unlock()
        request?.append(buffer)
    }

    private func currentRequest() -> SFSpeechAudioBufferRecognitionRequest? {
        lock.lock()
        defer { lock.unlock() }
        return request
    }

    /// Signals the end of audio and waits (up to 2 s) for the last words.
    func finish() async -> String {
        ended = true
        currentRequest()?.endAudio()
        if task == nil { return text }
        return await withCheckedContinuation { continuation in
            waiter = continuation
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in self?.resolve() }
        }
    }

    func cancel() {
        ended = true
        generation += 1
        task?.cancel()
        task = nil
        lock.lock()
        request = nil
        lock.unlock()
        resolve()
    }

    // MARK: - Internals (main queue)

    private func startTask() {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.contextualStrings = contextualStrings
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        lock.lock()
        self.request = request
        lock.unlock()

        generation += 1
        let gen = generation
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async { self?.handle(result, error, generation: gen) }
        }
    }

    private func handle(_ result: SFSpeechRecognitionResult?, _ error: Error?, generation gen: Int) {
        guard gen == generation else { return }
        if let result {
            let text = result.bestTranscription.formattedString
            onRaw?(text, result.isFinal, nil)
            stitcher.update(text) // detects the silent restart (see SegmentStitcher)
            onUpdate(self.text)
            if result.isFinal { segmentEnded() }
        } else if let error {
            onRaw?("", false, error)
            segmentEnded()
        }
    }

    private func segmentEnded() {
        stitcher.commit()
        task = nil
        if ended || restarts >= 30 {
            resolve()
        } else {
            restarts += 1
            startTask()
        }
    }

    private func resolve() {
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: text)
        }
    }
}
