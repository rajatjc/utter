import AppKit
import UtterCore

/// Feeds global key events into `ChordStateMachine` (UtterCore), which holds
/// the push-to-talk rules, and forwards its decisions.
@MainActor
final class HotkeyMonitor {
    var onPress: ((Mode) -> Void)?
    var onRelease: ((Mode) -> Void)?
    var onCancel: (() -> Void)?
    var onLock: ((Mode) -> Void)?
    /// Esc pressed at any time (used to dismiss confirmations).
    var onEscape: (() -> Void)?

    private var machine = ChordStateMachine()
    private var monitors: [Any] = []
    private let escapeKeyCode: UInt16 = 53

    // Diagnostics: counts of events received, so the log shows whether the
    // listener is still alive (which keys were typed is never recorded).
    private var modifierEvents = 0
    private var otherKeyEvents = 0
    private var lastEventAt: Date?
    private var heartbeat: Timer?

    var isLocked: Bool { machine.isLocked }

    func start() {
        guard monitors.isEmpty else { return }
        defer {
            Diagnostics.log("keys", "listener started: \(monitors.count) of 4 monitors installed, Accessibility trusted: \(AXIsProcessTrusted())")
            startHeartbeat()
        }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] e in
            MainActor.assumeIsolated { self?.handleFlags(e) }
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] e in
            MainActor.assumeIsolated { self?.handleFlags(e) }
            return e
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in
            MainActor.assumeIsolated { self?.handleKeyDown(e) }
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in
            MainActor.assumeIsolated { self?.handleKeyDown(e) }
            return e
        }) { monitors.append(m) }
    }

    /// Global monitors added before Accessibility was granted may never fire, so
    /// AppState calls this once the permission arrives.
    func restart() {
        Diagnostics.log("keys", "listener restarting")
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        reset()
        start()
    }

    /// A session started by clicking the bar: the chord now toggles it off.
    func beginExternal(_ mode: Mode) {
        machine.beginExternal(mode)
        Diagnostics.log("keys", "session started from the bar (\(mode.rawValue)); shortcut now toggles it off")
    }

    /// A session ended for reasons other than a key release.
    func reset() {
        if machine.active != nil || machine.isLocked {
            Diagnostics.log("keys", "shortcut state reset (was \(stateDescription))")
        }
        machine.reset()
    }

    private func handleFlags(_ event: NSEvent) {
        noteEvent(modifier: true)
        let before = stateDescription
        let actions = machine.flagsChanged(held: event.modifierFlags.rawValue,
                                           chords: Prefs.hotkey(for:), at: Date())
        let after = stateDescription
        // Every modifier change is logged (modifier names only), with what it did.
        let result = actions.isEmpty ? "no action" : actions.map(Self.describe).joined(separator: ", ")
        Diagnostics.log("keys", "modifiers: \(Diagnostics.modifiers(event.modifierFlags.rawValue)) → \(result)"
                        + (before == after ? "" : " [\(before) → \(after)]"))
        perform(actions)
    }

    private func handleKeyDown(_ event: NSEvent) {
        noteEvent(modifier: false)
        let isEscape = event.keyCode == escapeKeyCode
        if isEscape { onEscape?() }
        let actions = machine.keyDown(isEscape: isEscape)
        // Only keys that matter to Utter are logged, and never which key it was.
        if !actions.isEmpty || isEscape {
            let result = actions.isEmpty ? "no action" : actions.map(Self.describe).joined(separator: ", ")
            Diagnostics.log("keys", "\(isEscape ? "Esc" : "another key") pressed → \(result)")
        }
        perform(actions)
    }

    // MARK: Diagnostics

    private var stateDescription: String {
        guard let active = machine.active else { return "idle" }
        return machine.isLocked ? "\(active.rawValue), hands-free" : "\(active.rawValue) held"
    }

    private static func describe(_ action: ChordStateMachine.Action) -> String {
        switch action {
        case .press(let mode): "start \(mode.rawValue)"
        case .release(let mode): "finish \(mode.rawValue)"
        case .cancel: "cancel"
        case .lock(let mode): "hands-free \(mode.rawValue)"
        }
    }

    private func noteEvent(modifier: Bool) {
        if modifier { modifierEvents += 1 } else { otherKeyEvents += 1 }
        lastEventAt = Date()
    }

    /// Every 10 minutes: how many events arrived. Zero for a long stretch while
    /// you were typing means macOS stopped delivering key events to Utter.
    private func startHeartbeat() {
        heartbeat?.invalidate()
        heartbeat = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let last = self.lastEventAt.map { "\(Int(Date().timeIntervalSince($0)))s ago" } ?? "never"
                Diagnostics.log("keys", "heartbeat: \(self.modifierEvents) modifier and \(self.otherKeyEvents) other key events in 10 min, last \(last); monitors: \(self.monitors.count); Accessibility trusted: \(AXIsProcessTrusted()); shortcut state: \(self.stateDescription)")
                self.modifierEvents = 0
                self.otherKeyEvents = 0
            }
        }
    }

    private func perform(_ actions: [ChordStateMachine.Action]) {
        for action in actions {
            switch action {
            case .press(let mode): onPress?(mode)
            case .release(let mode): onRelease?(mode)
            case .cancel: onCancel?()
            case .lock(let mode): onLock?(mode)
            }
        }
    }
}
