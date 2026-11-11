import UtterCore
import AppKit
import Carbon.HIToolbox

/// Synthesizes keyboard events. Requires the Accessibility permission.
enum Keyboard {
    static func press(keyCode: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    static func paste() { press(keyCode: CGKeyCode(kVK_ANSI_V), flags: .maskCommand) }
    static func copy() { press(keyCode: CGKeyCode(kVK_ANSI_C), flags: .maskCommand) }

    /// Presses a shortcut written like "cmd+shift+t", "ctrl+cmd+q" or "escape".
    /// Returns false if it can't be parsed (see `ShortcutParser` in UtterCore).
    static func pressShortcut(_ spec: String) -> Bool {
        guard let shortcut = ShortcutParser.parse(spec) else { return false }
        var flags: CGEventFlags = []
        if shortcut.command { flags.insert(.maskCommand) }
        if shortcut.shift { flags.insert(.maskShift) }
        if shortcut.option { flags.insert(.maskAlternate) }
        if shortcut.control { flags.insert(.maskControl) }
        if shortcut.function { flags.insert(.maskSecondaryFn) }
        press(keyCode: CGKeyCode(shortcut.keyCode), flags: flags)
        return true
    }

    /// Play/pause, next and previous, sent as hardware media keys so they reach
    /// whichever player is active (Music, Spotify, browsers).
    static func mediaKey(_ key: Int32) {
        func post(down: Bool) {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = Int((key << 16) | ((down ? 0xA : 0xB) << 8))
            let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero, modifierFlags: flags,
                timestamp: 0, windowNumber: 0, context: nil,
                subtype: 8, data1: data1, data2: -1
            )
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
        post(down: true)
        post(down: false)
    }

    static let mediaPlayPause: Int32 = 16 // NX_KEYTYPE_PLAY
    static let mediaNext: Int32 = 17 // NX_KEYTYPE_NEXT
    static let mediaPrevious: Int32 = 18 // NX_KEYTYPE_PREVIOUS
}
