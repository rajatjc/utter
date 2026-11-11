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

    var isLocked: Bool { machine.isLocked }

    func start() {
        guard monitors.isEmpty else { return }
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
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        reset()
        start()
    }

    /// A session started by clicking the bar: the chord now toggles it off.
    func beginExternal(_ mode: Mode) { machine.beginExternal(mode) }

    /// A session ended for reasons other than a key release.
    func reset() { machine.reset() }

    private func handleFlags(_ event: NSEvent) {
        let actions = machine.flagsChanged(held: event.modifierFlags.rawValue,
                                           chords: Prefs.hotkey(for:), at: Date())
        perform(actions)
    }

    private func handleKeyDown(_ event: NSEvent) {
        let isEscape = event.keyCode == escapeKeyCode
        if isEscape { onEscape?() }
        perform(machine.keyDown(isEscape: isEscape))
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
