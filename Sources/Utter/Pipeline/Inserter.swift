import UtterCore
import AppKit

/// Puts finished text where the user is typing.
@MainActor
enum Inserter {
    enum Outcome {
        case typed
        /// Accessibility isn't granted, so the text went to the clipboard instead.
        case copiedToClipboard
    }

    static func insert(_ text: String, into target: NSRunningApplication?, canType: Bool) -> Outcome {
        guard canType else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            return .copiedToClipboard
        }
        // The overlay never takes focus, but the user may have clicked elsewhere.
        if let target, NSWorkspace.shared.frontmostApplication != target {
            target.activate()
        }
        TextIO.insert(text)
        return .typed
    }
}
