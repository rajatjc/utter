import UtterCore
import AppKit
import SwiftUI

enum Phase: Equatable {
    case idle
    case listening(Mode)
    case processing(Mode)
    case done(String)
    case failed(String)
    /// A brief informational message (e.g. "Muted").
    case notice(String)
    /// A command is waiting for the user to approve it (payload: the command).
    case confirm(String)
}

struct HistoryItem: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var mode: Mode
    var transcript: String
    var output: String
    var app: String?
}

/// Wires the hotkeys, speech, Claude and the overlay together.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var phase: Phase = .idle {
        didSet { if oldValue != phase { phaseSince = Date() } }
    }
    /// When the current phase began (drives the orb's completion animation).
    @Published var phaseSince = Date()
    @Published var liveTranscript = ""
    @Published var step = ""
    @Published var level: Float = 0
    @Published var handsFree = false
    @Published var barHovering = false
    /// The menu bar panel is open: the notch shouldn't open on top of it.
    var menuPanelOpen = false
    @Published var isMuted = false
    @Published var barStyle: Prefs.BarStyle = Prefs.barStyle
    @Published var confirmPurpose = ""
    /// Whether the current session shows live text (Apple recognizer) or just the waveform.
    @Published var livePreview = true
    @Published var listeningSince = Date()
    /// The mode of the current (or last) session, so later phases keep its layout.
    @Published var sessionMode: Mode?
    @Published var history: [HistoryItem] = []
    private var confirmation: CheckedContinuation<Bool, Never>?
    @Published var permissions = Permissions.Status()
    @Published var hasAPIKey = Keychain.apiKey() != nil
    /// True on Intel Macs too, where the Whisper step doesn't apply.
    @Published var whisperInstalled = !WhisperPaths.isSupported || WhisperPaths.python() != nil

    /// Setup steps done out of 4: microphone, speech, accessibility, Whisper.
    /// (The Claude API key is optional: it only enables Command mode.)
    var setupStepsDone: Int {
        [permissions.microphone, permissions.speech, permissions.accessibility, whisperInstalled].filter { $0 }.count
    }

    func clearHistory() {
        history = []
        HistoryStore.save(history)
    }

    private let speech = SpeechEngine()
    private let hotkeys = HotkeyMonitor()
    private lazy var hud = HUDController(state: self)

    private var focus = FocusContext()
    private var targetApp: NSRunningApplication?
    private var selectionAtStart: TextIO.Selection = .none
    private var work: Task<Void, Never>?
    /// Chosen when a session starts, so a settings change mid-session can't mix engines.
    private var transcriber: Transcriber?

    var menuBarSymbol: String {
        switch phase {
        case .listening: "mic.fill"
        case .processing: "ellipsis.circle"
        case .failed: "exclamationmark.triangle"
        default: isMuted ? "mic.slash" : "waveform"
        }
    }

    /// Mute pauses the hotkeys and the bar's buttons until unmuted.
    func toggleMute() {
        isMuted.toggle()
        if isMuted, case .listening = phase { cancel() }
    }

    func resetBarPosition() {
        hud.resetPosition()
    }

    func start() {
        history = HistoryStore.load()
        Permissions.requestAll { [weak self] in self?.refreshPermissions() }
        refreshPermissions()

        hotkeys.onPress = { [weak self] mode in self?.beginListening(mode) }
        hotkeys.onRelease = { [weak self] mode in self?.finishListening(mode) }
        hotkeys.onCancel = { [weak self] in self?.cancel() }
        hotkeys.onLock = { [weak self] _ in self?.handsFree = true }
        hotkeys.onEscape = { [weak self] in
            if case .confirm = self?.phase { self?.resolveConfirmation(false) }
        }
        hotkeys.start()
        hud.start()
        applySpeechEngine()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applySpeechEngine() }
        }

        // Watch for permission changes made in System Settings.
        Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissions() }
        }
    }

    /// Set by Snapshots so rendered screens keep their sample permissions.
    var frozenPermissions = false

    /// Starts the Whisper sidecar when it's the chosen recognizer; stops it (and
    /// frees its memory) when Apple's recognizer is chosen instead.
    private func applySpeechEngine() {
        let sidecar = WhisperSidecar.shared
        switch Prefs.speechEngine {
        case .whisper: if sidecar.status == .off, sidecar.isInstalled { sidecar.ensureRunning() }
        case .apple: if sidecar.status != .off { sidecar.stop() }
        }
    }

    func refreshPermissions() {
        guard !frozenPermissions else { return }
        let installed = !WhisperPaths.isSupported || WhisperPaths.python() != nil
        if installed != whisperInstalled { whisperInstalled = installed }
        let new = Permissions.current()
        guard new != permissions else { return }
        let gainedAccessibility = new.accessibility && !permissions.accessibility
        permissions = new
        if gainedAccessibility { hotkeys.restart() }
    }

    // MARK: Session lifecycle

    private func beginListening(_ mode: Mode) {
        if case .processing = phase { return }
        if isMuted {
            hotkeys.reset()
            return notice("Muted. Click the mic icon on the bar to unmute.")
        }
        work?.cancel()
        (focus, targetApp) = FocusContext.capture(includeWindowTitle: Prefs.sendWindowTitle)
        selectionAtStart = mode == .command ? TextIO.selectionViaAX() : .none
        liveTranscript = ""
        step = ""
        handsFree = false
        level = 0

        // The transcriber decides what to capture: a recording for Whisper, and
        // Apple's live recognizer only when its text is the result or a preview.
        let transcriber = Transcribers.current()
        self.transcriber = transcriber
        livePreview = transcriber.usesLiveRecognizer
        listeningSince = Date()
        sessionMode = mode
        do {
            try speech.start(
                locale: Prefs.locale,
                contextualStrings: Prefs.dictionaryWords + Prefs.snippets.map(\.trigger),
                useRecognizer: transcriber.usesLiveRecognizer,
                requireRecognizer: !transcriber.needsRecording,
                record: transcriber.needsRecording,
                onPartial: { [weak self] text in
                    MainActor.assumeIsolated { self?.liveTranscript = text }
                },
                onLevel: { [weak self] level in
                    MainActor.assumeIsolated { self?.level = level }
                }
            )
            phase = .listening(mode)
            hud.show()
            // Streaming transcribers start on the recording while the user talks.
            transcriber.begin(recording: speech.liveRecorder)
            if mode == .dictation, Prefs.dictationEngine == .apple { LocalModel.warmUp() }
        } catch {
            hotkeys.reset()
            fail(error.localizedDescription)
        }
    }

    private func finishListening(_ mode: Mode) {
        guard case .listening(let current) = phase, current == mode else { return }
        phase = .processing(mode)
        handsFree = false
        level = 0
        work = Task { [weak self] in
            guard let self else { return }
            let capture = await speech.stop()
            let transcriber = self.transcriber ?? AppleTranscriber()
            let transcript: String
            do {
                transcript = try await transcriber.transcribe(capture) { [weak self] in self?.step = $0 }
            } catch {
                return self.fail(error.localizedDescription)
            }
            guard !transcript.isEmpty else {
                self.fail("Didn't catch that.")
                return
            }
            self.liveTranscript = transcript
            switch mode {
            case .dictation: await self.runDictation(transcript)
            case .command: await self.runCommand(transcript)
            }
        }
    }

    func cancel() {
        if case .confirm = phase { return resolveConfirmation(false) }
        guard case .listening = phase else { return }
        speech.cancel()
        transcriber?.cancel()
        transcriber = nil
        hotkeys.reset()
        phase = .idle
        handsFree = false
        hud.settle(after: 0)
    }

    /// Shows a command under the notch and waits for Run / Cancel (45 s timeout).
    func confirm(command: String, purpose: String) async -> Bool {
        confirmation?.resume(returning: false)
        confirmPurpose = purpose
        phase = .confirm(command)
        hud.show()
        return await withCheckedContinuation { continuation in
            confirmation = continuation
            DispatchQueue.main.asyncAfter(deadline: .now() + 45) { [weak self] in
                self?.resolveConfirmation(false)
            }
        }
    }

    func resolveConfirmation(_ approved: Bool) {
        guard let confirmation else { return }
        self.confirmation = nil
        if case .confirm = phase {
            phase = .processing(.command)
            step = approved ? "Running…" : "Cancelled"
        }
        confirmation.resume(returning: approved)
    }

    /// Floating-bar buttons: click to start a hands-free session, click again to finish.
    func toggle(_ mode: Mode) {
        isMuted = false
        switch phase {
        case .listening(let current):
            if current == mode {
                hotkeys.reset()
                finishListening(mode)
            } else {
                cancel()
            }
        case .processing:
            return
        default:
            beginListening(mode)
            if case .listening = phase {
                handsFree = true
                hotkeys.beginExternal(mode)
            }
        }
    }

    // MARK: Modes

    /// Dictation pipeline: transcript → cleaner → inserter.
    private func runDictation(_ transcript: String) async {
        let cleaner = Cleaners.current(hasAPIKey: hasAPIKey)
        var output: String
        var note: String?
        step = "Polishing…"
        do {
            output = try await cleaner.clean(transcript, context: focus)
        } catch {
            output = BasicCleaner.clean(transcript, snippets: Prefs.snippets)
            note = "Inserted without AI cleanup: \(error.localizedDescription)"
        }
        guard !output.isEmpty else { return complete("Nothing to insert.") }

        record(.dictation, transcript, output)
        switch Inserter.insert(output, into: targetApp, canType: permissions.accessibility) {
        case .typed:
            complete(note ?? "Inserted \(output.split(separator: " ").count) words", linger: note == nil ? 1.4 : 4)
        case .copiedToClipboard:
            complete("Copied to clipboard. Turn on Accessibility so Utter can type for you.", linger: 5)
        }
    }

    private func runCommand(_ transcript: String) async {
        guard hasAPIKey else {
            return fail("Voice commands need a Claude API key. Add one in Settings → AI.")
        }
        step = "Thinking…"
        reactivateTarget()
        var selection: String?
        switch selectionAtStart {
        case .text(let text): selection = text
        case .none: selection = nil
        case .unknown:
            // Code editors copy the whole line on Cmd+C with no selection, so skip them.
            if !focus.isCodeEditor { selection = await TextIO.selectedTextViaCopy() }
        }
        let agent = CommandAgent(onStep: { [weak self] text in self?.step = text })
        do {
            let reply = try await agent.run(instruction: transcript, selectedText: selection, focus: focus)
            record(.command, transcript, reply)
            complete(reply, linger: 4)
        } catch {
            fail(error.localizedDescription)
        }
    }

    // MARK: Helpers

    private func reactivateTarget() {
        // The overlay never takes focus, but the user may have clicked elsewhere.
        if let targetApp, NSWorkspace.shared.frontmostApplication != targetApp {
            targetApp.activate()
        }
    }

    private func record(_ mode: Mode, _ transcript: String, _ output: String) {
        history.insert(HistoryItem(mode: mode, transcript: transcript, output: output, app: focus.appName), at: 0)
        if history.count > 200 { history.removeLast(history.count - 200) }
        HistoryStore.save(history)
    }

    private func complete(_ message: String, linger: TimeInterval = 0.8) {
        phase = .done(message)
        hud.settle(after: linger)
        scheduleIdle(after: linger)
    }

    private func fail(_ message: String) {
        phase = .failed(message)
        hud.show()
        hud.settle(after: 4)
        scheduleIdle(after: 4)
    }

    private func notice(_ message: String) {
        phase = .notice(message)
        hud.show()
        hud.settle(after: 2.5)
        scheduleIdle(after: 2.5)
    }

    private func scheduleIdle(after delay: TimeInterval) {
        let current = phase
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.phase == current else { return }
            self.phase = .idle
        }
    }
}

enum HistoryStore {
    private static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Utter", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }

    static func load() -> [HistoryItem] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([HistoryItem].self, from: data)) ?? []
    }

    static func save(_ items: [HistoryItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
