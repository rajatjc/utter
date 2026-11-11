import UtterCore
import AppKit

/// Where the user is typing, used to match tone and formatting.
struct FocusContext {
    var appName: String?
    var bundleID: String?
    var windowTitle: String?

    @MainActor
    static func capture(includeWindowTitle: Bool) -> (FocusContext, NSRunningApplication?) {
        let app = NSWorkspace.shared.frontmostApplication
        let context = FocusContext(
            appName: app?.localizedName,
            bundleID: app?.bundleIdentifier,
            windowTitle: includeWindowTitle ? TextIO.focusedWindowTitle(of: app) : nil
        )
        return (context, app)
    }

    private static let codeApps = ["xcode", "vscode", "cursor", "zed", "jetbrains", "sublime", "terminal", "iterm", "warp", "ghostty", "nova", "windsurf"]

    var isCodeEditor: Bool {
        let id = (bundleID ?? "").lowercased()
        return Self.codeApps.contains(where: id.contains)
    }

    /// Style guidance by app category.
    var styleHint: String {
        let id = (bundleID ?? "").lowercased()
        let title = (windowTitle ?? "").lowercased()
        let messaging = ["slack", "com.apple.mobilesms", "discord", "whatsapp", "telegram", "signal", "teams", "messenger"]
        let email = ["com.apple.mail", "outlook", "superhuman", "spark", "mimestream"]
        let notes = ["notion", "obsidian", "com.apple.notes", "bear", "craft", "pages", "word", "logseq"]

        if messaging.contains(where: id.contains) {
            return "Chat message: conversational and concise. Light punctuation; no sign-off."
        }
        if email.contains(where: id.contains) || title.contains("gmail") || title.contains("inbox") {
            return "Email: complete sentences and paragraphs. If the speaker dictates a greeting or sign-off, put each on its own line."
        }
        if isCodeEditor {
            return "Code editor or terminal: keep technical terms, identifiers and commands exact (e.g. \"snake case user id\" becomes user_id, \"camel case user id\" becomes userId). Don't add a trailing period to a command or code."
        }
        if notes.contains(where: id.contains) {
            return "Notes or document: well-formed prose. Markdown bullet lists are fine for lists."
        }
        return "General text: clear, natural writing."
    }

    var promptDescription: String {
        var lines: [String] = []
        if let appName { lines.append("App: \(appName)") }
        if let windowTitle, !windowTitle.isEmpty { lines.append("Window: \(windowTitle)") }
        lines.append("Style: \(styleHint)")
        return lines.joined(separator: "\n")
    }
}
