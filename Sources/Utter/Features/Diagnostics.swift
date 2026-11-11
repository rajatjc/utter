import AppKit
import Foundation
import os

/// A plain-text diagnostics log at ~/Library/Application Support/Utter/diagnostics.log,
/// for working out why something stopped (for example the hotkeys after sleep).
///
/// Privacy rule: it records which *modifier* keys are held and how many other
/// keys were pressed, never which letters or words, and never dictated text.
/// The file is capped at 2 MB (the previous one is kept as diagnostics.1.log).
enum Diagnostics {
    private static let queue = DispatchQueue(label: "dev.utter.diagnostics")
    private static let logger = Logger(subsystem: "dev.utter.Utter", category: "diagnostics")
    private static let maxBytes = 2_000_000

    static var fileURL: URL { WhisperPaths.supportDirectory.appendingPathComponent("diagnostics.log") }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    /// `area` groups lines (keys, power, session, permissions, app).
    static func log(_ area: String, _ message: String) {
        let line = "\(formatter.string(from: Date())) [\(area)] \(message)\n"
        logger.info("[\(area, privacy: .public)] \(message, privacy: .public)")
        queue.async { append(line) }
    }

    private static func append(_ line: String) {
        let url = fileURL
        let fm = FileManager.default
        if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > maxBytes {
            let old = url.deletingLastPathComponent().appendingPathComponent("diagnostics.1.log")
            try? fm.removeItem(at: old)
            try? fm.moveItem(at: url, to: old)
        }
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            fm.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
    }

    // MARK: Modifier description

    /// Names the held modifiers from the device-dependent bits, e.g. "L⌃ L⌥".
    static func modifiers(_ raw: UInt) -> String {
        let names: [(UInt, String)] = [
            (0x0001, "L⌃"), (0x2000, "R⌃"), (0x0020, "L⌥"), (0x0040, "R⌥"),
            (0x0008, "L⌘"), (0x0010, "R⌘"), (0x0002, "L⇧"), (0x0004, "R⇧"),
        ]
        let held = names.filter { raw & $0.0 != 0 }.map(\.1)
        var parts = held.isEmpty ? ["none"] : held
        if raw & NSEvent.ModifierFlags.function.rawValue != 0 { parts.append("fn") }
        if raw & NSEvent.ModifierFlags.capsLock.rawValue != 0 { parts.append("caps") }
        return parts.joined(separator: " ")
    }

    // MARK: Sleep, wake and lock

    private static var observers: [NSObjectProtocol] = []

    /// Logs launch details and every sleep, wake, screen lock and unlock.
    @MainActor
    static func start() {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        log("app", "launched: version \(version) (\(build)), pid \(ProcessInfo.processInfo.processIdentifier), macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")

        let workspace = NSWorkspace.shared.notificationCenter
        let events: [(NotificationCenter, Notification.Name, String)] = [
            (workspace, NSWorkspace.willSleepNotification, "Mac going to sleep"),
            (workspace, NSWorkspace.didWakeNotification, "Mac woke up"),
            (workspace, NSWorkspace.screensDidSleepNotification, "displays slept"),
            (workspace, NSWorkspace.screensDidWakeNotification, "displays woke"),
            (workspace, NSWorkspace.sessionDidResignActiveNotification, "user session inactive (fast user switching)"),
            (workspace, NSWorkspace.sessionDidBecomeActiveNotification, "user session active"),
            (DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsLocked"), "screen locked"),
            (DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsUnlocked"), "screen unlocked"),
        ]
        for (center, name, text) in events {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in log("power", text) })
        }
    }
}
