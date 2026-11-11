import Foundation

/// Modifier-key chords, identified by the left/right-specific hardware bits
/// (NX_DEVICE*KEYMASK) that `NSEvent.modifierFlags.rawValue` carries.
public enum HotkeyChord: String, CaseIterable, Identifiable, Sendable {
    case leftControlOption, leftControlCommand, leftOptionCommand
    case rightOption, rightCommand, rightControl

    public var id: String { rawValue }

    /// All left/right-specific modifier bits.
    public static let deviceBits: UInt = 0x01 | 0x02 | 0x04 | 0x08 | 0x10 | 0x20 | 0x40 | 0x2000

    public var label: String {
        switch self {
        case .leftControlOption: "Left ⌃ + Left ⌥"
        case .leftControlCommand: "Left ⌃ + Left ⌘"
        case .leftOptionCommand: "Left ⌥ + Left ⌘"
        case .rightOption: "Right ⌥"
        case .rightCommand: "Right ⌘"
        case .rightControl: "Right ⌃"
        }
    }

    public var mask: UInt {
        switch self {
        case .leftControlOption: 0x01 | 0x20
        case .leftControlCommand: 0x01 | 0x08
        case .leftOptionCommand: 0x20 | 0x08
        case .rightOption: 0x40
        case .rightCommand: 0x10
        case .rightControl: 0x2000
        }
    }
}

/// Push-to-talk rules, independent of AppKit so they can be checked:
///
/// - Hold a chord: start; release: finish. Starts only on the exact chord.
/// - A tap shorter than `tapThreshold` cancels; two dictation taps within
///   `doubleTapWindow` lock hands-free mode, and the next press finishes.
/// - An extra modifier or any key while holding cancels (the user is doing a
///   shortcut); Esc cancels a hands-free session.
public struct ChordStateMachine: Sendable {
    public enum Action: Equatable, Sendable {
        case press(Mode)
        case release(Mode)
        case cancel
        case lock(Mode)
    }

    public var tapThreshold: TimeInterval = 0.3
    public var doubleTapWindow: TimeInterval = 0.5

    public private(set) var active: Mode?
    public private(set) var isLocked = false
    private var chordHeld: [Mode: Bool] = [:]
    private var pressedAt = Date.distantPast
    private var lastTapAt = Date.distantPast
    private var ignoreNextRelease = false

    public init() {}

    /// Modifier state changed. `held` is the raw modifier flags (device bits are extracted).
    public mutating func flagsChanged(held raw: UInt, chords: (Mode) -> HotkeyChord, at now: Date) -> [Action] {
        let held = raw & HotkeyChord.deviceBits
        var actions: [Action] = []
        for mode in [Mode.dictation, .command] {
            let chord = chords(mode).mask
            let wasHeld = chordHeld[mode] ?? false
            let isHeld = held & chord == chord
            chordHeld[mode] = isHeld
            if isHeld, !wasHeld {
                if held == chord { actions += chordDown(mode, at: now) }
            } else if !isHeld, wasHeld {
                actions += chordUp(mode, at: now)
            }
        }
        if let active, !isLocked, held & ~chords(active).mask != 0 {
            actions += cancel(keyHeld: true)
        }
        return actions
    }

    /// A non-modifier key went down.
    public mutating func keyDown(isEscape: Bool) -> [Action] {
        guard active != nil else { return [] }
        if isEscape || !isLocked { return cancel(keyHeld: !isLocked) }
        return []
    }

    /// A session started some other way (clicking the bar): the chord now
    /// toggles it off, like hands-free mode.
    public mutating func beginExternal(_ mode: Mode) {
        active = mode
        isLocked = true
        ignoreNextRelease = false
    }

    public mutating func reset() {
        active = nil
        isLocked = false
        ignoreNextRelease = false
    }

    private mutating func chordDown(_ mode: Mode, at now: Date) -> [Action] {
        if isLocked, let lockedMode = active {
            isLocked = false
            active = nil
            ignoreNextRelease = true
            return [.release(lockedMode)]
        }
        guard active == nil else { return [] }
        active = mode
        pressedAt = now
        return [.press(mode)]
    }

    private mutating func chordUp(_ mode: Mode, at now: Date) -> [Action] {
        if ignoreNextRelease { ignoreNextRelease = false; return [] }
        guard active == mode, !isLocked else { return [] }
        if now.timeIntervalSince(pressedAt) < tapThreshold {
            if mode == .dictation, now.timeIntervalSince(lastTapAt) < doubleTapWindow {
                isLocked = true
                lastTapAt = .distantPast
                return [.lock(mode)]
            }
            lastTapAt = now
            return cancel(keyHeld: false)
        }
        active = nil
        return [.release(mode)]
    }

    /// `keyHeld`: the chord is still physically down, so its release is ignored.
    private mutating func cancel(keyHeld: Bool) -> [Action] {
        active = nil
        isLocked = false
        ignoreNextRelease = keyHeld
        return [.cancel]
    }
}

/// Parses shortcuts written like "cmd+shift+t", "ctrl+cmd+q" or "escape".
public enum ShortcutParser {
    public struct Shortcut: Equatable, Sendable {
        public var keyCode: Int
        public var command = false, shift = false, option = false, control = false, function = false

        public init(keyCode: Int, command: Bool = false, shift: Bool = false, option: Bool = false,
                    control: Bool = false, function: Bool = false) {
            self.keyCode = keyCode
            self.command = command
            self.shift = shift
            self.option = option
            self.control = control
            self.function = function
        }
    }

    public static func parse(_ spec: String) -> Shortcut? {
        let parts = spec.lowercased().replacingOccurrences(of: " ", with: "").split(separator: "+").map(String.init)
        guard let keyName = parts.last, let code = keyCodes[keyName] else { return nil }
        var shortcut = Shortcut(keyCode: code)
        for modifier in parts.dropLast() {
            switch modifier {
            case "cmd", "command", "⌘": shortcut.command = true
            case "shift", "⇧": shortcut.shift = true
            case "opt", "option", "alt", "⌥": shortcut.option = true
            case "ctrl", "control", "⌃": shortcut.control = true
            case "fn": shortcut.function = true
            default: return nil
            }
        }
        return shortcut
    }

    /// US ANSI virtual key codes (kVK_* in Carbon's Events.h).
    static let keyCodes: [String: Int] = {
        var map: [String: Int] = [
            "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07,
            "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10,
            "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "=": 0x18,
            "9": 0x19, "7": 0x1A, "-": 0x1B, "8": 0x1C, "0": 0x1D, "]": 0x1E, "o": 0x1F, "u": 0x20,
            "[": 0x21, "i": 0x22, "p": 0x23, "l": 0x25, "j": 0x26, "'": 0x27, "k": 0x28, ";": 0x29,
            "\\": 0x2A, ",": 0x2B, "/": 0x2C, "n": 0x2D, "m": 0x2E, ".": 0x2F, "`": 0x32,
            "return": 0x24, "enter": 0x24, "tab": 0x30, "space": 0x31, "delete": 0x33, "backspace": 0x33,
            "escape": 0x35, "esc": 0x35, "forwarddelete": 0x75, "home": 0x73, "end": 0x77,
            "pageup": 0x74, "pagedown": 0x79, "left": 0x7B, "right": 0x7C, "down": 0x7D, "up": 0x7E,
        ]
        let fKeys = [0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D, 0x67, 0x6F]
        for (i, code) in fKeys.enumerated() { map["f\(i + 1)"] = code }
        return map
    }()
}
