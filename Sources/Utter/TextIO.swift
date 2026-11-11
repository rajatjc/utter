import UtterCore
import AppKit
import ApplicationServices

/// Reads context from, and writes text into, whatever app has keyboard focus.
@MainActor
enum TextIO {
    /// Inserts text at the cursor (replacing any selection) by pasting, then
    /// restores the user's clipboard.
    static func insert(_ text: String) {
        let board = NSPasteboard.general
        let saved = snapshot(board)
        board.clearContents()
        board.setString(text, forType: .string)
        // Tells clipboard managers not to record this entry.
        board.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        let ourChange = board.changeCount
        Keyboard.paste()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            // Only restore if nothing else has written to the clipboard since.
            guard board.changeCount == ourChange else { return }
            restore(saved, to: board)
        }
    }

    enum Selection {
        case text(String)
        case none
        /// The app doesn't report selection over Accessibility.
        case unknown
    }

    /// Selected text in the focused element, read through the Accessibility API.
    static func selectionViaAX() -> Selection {
        guard let element = focusedElement() else { return .unknown }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success
        else { return .unknown }
        if let text = value as? String, !text.isEmpty { return .text(text) }
        return .none
    }

    /// Fallback for apps that don't expose selection over Accessibility (many
    /// Electron apps and browsers): press Cmd+C and read the clipboard.
    static func selectedTextViaCopy() async -> String? {
        let board = NSPasteboard.general
        let saved = snapshot(board)
        let before = board.changeCount
        Keyboard.copy()
        try? await Task.sleep(nanoseconds: 180_000_000)
        guard board.changeCount != before else { return nil }
        let text = board.string(forType: .string)
        restore(saved, to: board)
        return (text?.isEmpty == false) ? text : nil
    }

    static func focusedWindowTitle(of app: NSRunningApplication?) -> String? {
        guard let app else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window
        else { return nil }
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success
        else { return nil }
        return title as? String
    }

    private static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused
        else { return nil }
        return (focused as! AXUIElement)
    }

    private typealias Snapshot = [[NSPasteboard.PasteboardType: Data]]

    private static func snapshot(_ board: NSPasteboard) -> Snapshot {
        (board.pasteboardItems ?? []).map { item in
            var entry: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { entry[type] = data }
            }
            return entry
        }
    }

    private static func restore(_ snapshot: Snapshot, to board: NSPasteboard) {
        board.clearContents()
        let items = snapshot.map { entry -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entry { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { board.writeObjects(items) }
    }
}
