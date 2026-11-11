import UtterCore
import AppKit

struct ActionResult {
    var message: String
    var isError = false

    static func ok(_ message: String) -> ActionResult { ActionResult(message: message) }
    static func fail(_ message: String) -> ActionResult { ActionResult(message: message, isError: true) }
}

/// The fixed set of things command mode can do on the Mac. There is
/// deliberately no "run any script" action: everything here is bounded.
@MainActor
enum MacActions {
    // MARK: Apps and the web

    static func openApp(_ name: String) async -> ActionResult {
        guard let url = findApp(named: name) else {
            let suggestions = installedApps().map(\.name).filter {
                $0.lowercased().contains(name.lowercased().prefix(3))
            }.prefix(8)
            return .fail("No app named \"\(name)\". Similar: \(suggestions.joined(separator: ", "))")
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        do {
            try await NSWorkspace.shared.openApplication(at: url, configuration: config)
            return .ok("Opened \(url.deletingPathExtension().lastPathComponent)")
        } catch {
            return .fail("Couldn't open \(name): \(error.localizedDescription)")
        }
    }

    static func quitApp(_ name: String) -> ActionResult {
        let target = name.lowercased()
        let matches = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && ($0.localizedName?.lowercased() == target)
        }
        guard !matches.isEmpty else { return .fail("\(name) isn't running") }
        matches.forEach { $0.terminate() }
        return .ok("Quit \(name)")
    }

    static func openURL(_ string: String) -> ActionResult {
        var s = string.trimmingCharacters(in: .whitespaces)
        if !s.contains("://") { s = "https://" + s }
        guard let url = URL(string: s), url.scheme == "https" || url.scheme == "http" else {
            return .fail("Not a web URL: \(string)")
        }
        NSWorkspace.shared.open(url)
        return .ok("Opened \(url.absoluteString)")
    }

    static func webSearch(_ query: String) -> ActionResult {
        var components = URLComponents(string: "https://www.google.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        NSWorkspace.shared.open(components.url!)
        return .ok("Searched the web for \(query)")
    }

    // MARK: Text and keys

    static func typeText(_ text: String) -> ActionResult {
        TextIO.insert(text)
        return .ok("Inserted \(text.count) characters")
    }

    static func pressShortcut(_ keys: String) -> ActionResult {
        Keyboard.pressShortcut(keys) ? .ok("Pressed \(keys)") : .fail("Unknown key combination: \(keys)")
    }

    // MARK: System

    static func setVolume(_ percent: Int) -> ActionResult {
        let value = max(0, min(100, percent))
        return runAppleScript("set volume output volume \(value)", success: "Volume set to \(value)%")
    }

    static func media(_ action: String) -> ActionResult {
        switch action {
        case "play_pause": Keyboard.mediaKey(Keyboard.mediaPlayPause)
        case "next": Keyboard.mediaKey(Keyboard.mediaNext)
        case "previous": Keyboard.mediaKey(Keyboard.mediaPrevious)
        default: return .fail("Unknown media action \(action)")
        }
        return .ok("Media: \(action)")
    }

    static func system(_ action: String) async -> ActionResult {
        switch action {
        case "toggle_dark_mode":
            return runAppleScript(
                "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode",
                success: "Toggled dark mode"
            )
        case "lock_screen":
            _ = Keyboard.pressShortcut("ctrl+cmd+q")
            return .ok("Locked the screen")
        case "sleep_display":
            let result = await Shell.run("/usr/bin/pmset", ["displaysleepnow"])
            return result.status == 0 ? .ok("Display asleep") : .fail(result.output)
        case "show_desktop":
            _ = Keyboard.pressShortcut("cmd+f3")
            return .ok("Showed the desktop")
        default:
            return .fail("Unknown system action \(action)")
        }
    }

    // MARK: Terminal

    /// Shows the exact command under the notch; runs it in Terminal only after
    /// the user clicks Run. Terminal keeps the output visible.
    static func runCommand(_ command: String, purpose: String) async -> ActionResult {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .fail("Empty command") }
        let approved = await AppState.shared.confirm(command: trimmed, purpose: purpose)
        guard approved else {
            return .fail("The user declined to run this command. Don't retry it; just say it was cancelled.")
        }
        return runAppleScript("""
        tell application "Terminal"
            activate
            do script \(quoted(trimmed))
        end tell
        """, success: "Started in Terminal: \(trimmed)")
    }

    // MARK: Reminders, Notes, Shortcuts

    static func createReminder(title: String, due: String) -> ActionResult {
        var script = ""
        var properties = "name:\(quoted(title))"
        if !due.isEmpty {
            guard let date = parseLocalDate(due) else { return .fail("Couldn't read the date \(due)") }
            let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            // Set the day to 1 first so changing the month can't overflow (e.g. Jan 31 → Feb).
            script = """
            set d to current date
            set day of d to 1
            set year of d to \(c.year!)
            set month of d to \(c.month!)
            set day of d to \(c.day!)
            set hours of d to \(c.hour!)
            set minutes of d to \(c.minute!)
            set seconds of d to 0

            """
            properties += ", due date:d, remind me date:d"
        }
        script += "tell application \"Reminders\" to make new reminder with properties {\(properties)}"
        return runAppleScript(script, success: "Created reminder \"\(title)\"\(due.isEmpty ? "" : " for \(due)")")
    }

    static func createNote(title: String, body: String) -> ActionResult {
        let html = "<h1>\(escapeHTML(title))</h1>" + escapeHTML(body).replacingOccurrences(of: "\n", with: "<br>")
        return runAppleScript(
            "tell application \"Notes\" to make new note with properties {body:\(quoted(html))}",
            success: "Created note \"\(title)\""
        )
    }

    /// The user's Apple Shortcuts, so any of their automations becomes a voice command.
    static func shortcutNames() async -> [String] {
        let result = await Shell.run("/usr/bin/shortcuts", ["list"], timeout: 5)
        guard result.status == 0 else { return [] }
        return result.output.split(whereSeparator: \.isNewline).map(String.init)
    }

    static func runShortcut(_ name: String, input: String) async -> ActionResult {
        var args = ["run", name]
        var inputFile: URL?
        if !input.isEmpty {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("utter-shortcut-input.txt")
            try? input.write(to: url, atomically: true, encoding: .utf8)
            args += ["--input-path", url.path]
            inputFile = url
        }
        let result = await Shell.run("/usr/bin/shortcuts", args, timeout: 60)
        if let inputFile { try? FileManager.default.removeItem(at: inputFile) }
        if result.status == 0 {
            let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            return .ok(output.isEmpty ? "Ran shortcut \(name)" : "Ran shortcut \(name). Output: \(output.prefix(2000))")
        }
        return .fail("Shortcut \(name) failed: \(result.output.prefix(500))")
    }

    // MARK: Helpers

    struct InstalledApp { let name: String; let url: URL }

    static func installedApps() -> [InstalledApp] {
        let dirs = [
            "/Applications", "/Applications/Utilities", "/System/Applications",
            "/System/Applications/Utilities", NSHomeDirectory() + "/Applications",
            "/System/Library/CoreServices",
        ]
        var apps: [InstalledApp] = []
        for dir in dirs {
            let items = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
            for item in items where item.hasSuffix(".app") {
                apps.append(InstalledApp(
                    name: String(item.dropLast(4)),
                    url: URL(fileURLWithPath: dir).appendingPathComponent(item)
                ))
            }
        }
        return apps
    }

    private static func findApp(named name: String) -> URL? {
        let target = name.lowercased()
            .replacingOccurrences(of: ".app", with: "")
            .trimmingCharacters(in: .whitespaces)
        if target.contains("."), let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target) {
            return url
        }
        let apps = installedApps()
        let lowered = apps.map { ($0, $0.name.lowercased()) }
        return lowered.first(where: { $0.1 == target })?.0.url
            ?? lowered.first(where: { $0.1.hasPrefix(target) })?.0.url
            ?? lowered.first(where: { $0.1.contains(target) })?.0.url
    }

    private static func runAppleScript(_ source: String, success: String) -> ActionResult {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            let message = error[NSAppleScript.errorMessage] as? String ?? "AppleScript failed"
            return .fail(message)
        }
        return .ok(success)
    }

    private static func quoted(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func parseLocalDate(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: s) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            f.dateFormat = format
            if let d = f.date(from: s) { return d }
        }
        return nil
    }
}

enum Shell {
    struct Result { let status: Int32; let output: String }

    /// Runs a program off the main thread, killing it after `timeout` seconds.
    static func run(_ path: String, _ args: [String], timeout: TimeInterval = 10) async -> Result {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = args
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do { try process.run() } catch {
                return Result(status: -1, output: error.localizedDescription)
            }
            let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            killer.cancel()
            return Result(status: process.terminationStatus, output: String(data: data, encoding: .utf8) ?? "")
        }.value
    }
}
