import UtterCore
import Foundation

/// User preferences. SettingsView binds to the same keys with @AppStorage.
enum Prefs {
    static let modelKey = "model"
    static let cleanupKey = "cleanupEnabled"
    static let dictionaryKey = "dictionary"
    static let snippetsKey = "snippets"
    static let localeKey = "locale"
    static let sendWindowTitleKey = "sendWindowTitle"

    // MARK: Speech recognition

    enum SpeechEngine: String {
        case apple    // SFSpeechRecognizer: built in, live partial results
        case whisper  // Whisper large-v3-turbo via the local mlx-whisper sidecar
    }

    static let speechEngineKey = "speechEngine"
    static let whisperPythonKey = "whisperPython"
    static let whisperModelKey = "whisperModel"
    static let defaultWhisperModel = "mlx-community/whisper-large-v3-turbo"

    static var speechEngine: SpeechEngine {
        if let raw = defaults.string(forKey: speechEngineKey), let engine = SpeechEngine(rawValue: raw) {
            return engine
        }
        return WhisperPaths.python() != nil ? .whisper : .apple
    }

    /// With Whisper, run Apple's recognizer too just for a live text preview.
    /// Off by default: that preview drops words after pauses and isn't needed.
    static let showLiveTextKey = "showLiveText"
    static var showLiveText: Bool { defaults.object(forKey: showLiveTextKey) as? Bool ?? false }

    /// Optional override for the Python interpreter that has mlx-whisper installed.
    static var whisperPython: String { defaults.string(forKey: whisperPythonKey) ?? "" }

    static var whisperModel: String {
        let value = defaults.string(forKey: whisperModelKey) ?? ""
        return value.isEmpty ? defaultWhisperModel : value
    }

    /// Two-letter language code for Whisper (skips auto-detection), e.g. "en".
    static var whisperLanguage: String? {
        locale.language.languageCode?.identifier
    }

    static let dictationEngineKey = "dictationEngine"

    enum Engine: String {
        case apple   // on-device, free
        case claude  // cloud, best quality, needs an API key
    }

    static var dictationEngine: Engine {
        Engine(rawValue: defaults.string(forKey: dictationEngineKey) ?? "") ?? .apple
    }

    /// Whether the bar stays on screen while idle (so it can be hovered and clicked).
    static let showFloatingBarKey = "showFloatingBar"
    static var showBarWhenIdle: Bool { defaults.object(forKey: showFloatingBarKey) as? Bool ?? true }

    /// The island in the notch on Macs that have one; a draggable floating pill
    /// on Macs without (iMac, Mac mini with a display, older MacBooks).
    enum BarStyle: String {
        case notch, floating
    }

    @MainActor
    static var barStyle: BarStyle { NotchGeometry.current().hasNotch ? .notch : .floating }

    /// Where the user last dragged the floating bar: horizontal center plus the
    /// top edge (when docked near the top of the screen) or bottom edge.
    struct BarAnchor: Equatable {
        var x: CGFloat
        var y: CGFloat
        var fromTop: Bool
    }

    static var barAnchor: BarAnchor? {
        get {
            guard let x = defaults.object(forKey: "barAnchorX") as? Double,
                  let y = defaults.object(forKey: "barAnchorY") as? Double else { return nil }
            return BarAnchor(x: x, y: y, fromTop: defaults.bool(forKey: "barAnchorTop"))
        }
        set {
            defaults.set(newValue?.x, forKey: "barAnchorX")
            defaults.set(newValue?.y, forKey: "barAnchorY")
            defaults.set(newValue?.fromTop ?? true, forKey: "barAnchorTop")
        }
    }

    // MARK: Hotkeys

    typealias HotkeyChord = UtterCore.HotkeyChord

    static let dictationHotkeyKey = "dictationHotkey"
    static let commandHotkeyKey = "commandHotkey"

    static func hotkey(for mode: Mode) -> HotkeyChord {
        switch mode {
        case .dictation:
            HotkeyChord(rawValue: defaults.string(forKey: dictationHotkeyKey) ?? "") ?? .leftControlOption
        case .command:
            HotkeyChord(rawValue: defaults.string(forKey: commandHotkeyKey) ?? "") ?? .rightCommand
        }
    }

    static let defaultModel = "claude-haiku-5-5"
    static let models: [(id: String, name: String, tagline: String)] = [
        ("claude-opus-5-5", "Opus 5.5", "Best quality"),
        ("claude-sonnet-5-5", "Sonnet 5.5", "Balanced"),
        ("claude-haiku-5-5", "Haiku 5.5", "Fastest, cheapest"),
    ]

    private static var defaults: UserDefaults { .standard }

    static var model: String { defaults.string(forKey: modelKey) ?? defaultModel }
    static var cleanupEnabled: Bool { defaults.object(forKey: cleanupKey) as? Bool ?? true }
    static var sendWindowTitle: Bool { defaults.object(forKey: sendWindowTitleKey) as? Bool ?? true }

    static var locale: Locale {
        if let id = defaults.string(forKey: localeKey), !id.isEmpty { return Locale(identifier: id) }
        return Locale.current
    }

    /// One custom word or name per line (product names, people, jargon).
    static var dictionaryWords: [String] {
        PersonalDictionary.parse(defaults.string(forKey: dictionaryKey) ?? "")
    }

    /// Lines of the form `trigger => expansion`, e.g. `my email => you@example.com`.
    static var snippets: [Snippet] {
        Snippet.parse(defaults.string(forKey: snippetsKey) ?? "")
    }
}
