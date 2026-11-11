import UtterCore
import Foundation

/// Command mode: the user speaks an instruction and Claude carries it out with
/// a fixed set of Mac tools. This is a manual tool-use loop over raw HTTP.
@MainActor
struct CommandAgent {
    var onStep: (String) -> Void = { _ in }

    private static let maxTurns = 8

    private static let system = """
    You are the command mode of Utter, a voice layer for macOS. The user held a key, spoke an \
    instruction, and you carry it out on their Mac with the tools provided. You're told which \
    app they're in and, if they had text selected, what it is.

    - Act; don't ask. The user can't answer follow-up questions in this mode, so when a request \
    is ambiguous, take the most likely reading.
    - If text is selected and the instruction is about that text ("make this more formal", \
    "translate to Spanish", "fix the grammar", "turn this into bullet points"), call type_text with \
    the rewritten text. It replaces the selection.
    - If the user asks you to write something ("reply saying I'll be ten minutes late"), write it \
    in their voice and insert it with type_text into the current app.
    - If the user asks a question, answer it in your final reply without using tools.
    - Your final reply is shown in a small overlay for a few seconds: one or two short sentences. \
    After acting, confirm what you did in under 12 words, e.g. "Opened Safari and searched for \
    flights to Lisbon."
    - Use only the tools given. If the request needs something they can't do, say so briefly.
    - Prefer the user's Apple Shortcuts (listed in the context) when one clearly matches the request.
    - For anything a developer would type in Terminal (run a script, git, build, install), use \
    run_command with one complete zsh command. The user sees it and must click Run, so make it \
    exactly right the first time; don't split it into several calls. If they cancel, stop.
    """

    func run(instruction: String, selectedText: String?, focus: FocusContext) async throws -> String {
        let client = try ClaudeClient.fromPrefs()
        let shortcuts = await MacActions.shortcutNames()

        var context: [String] = []
        let now = Date()
        context.append("Current local time: \(now.formatted(date: .complete, time: .shortened)) (\(TimeZone.current.identifier))")
        context.append("User's home folder: \(NSHomeDirectory()); shell: zsh")
        context.append(focus.promptDescription)
        if !shortcuts.isEmpty {
            context.append("User's Apple Shortcuts: \(shortcuts.prefix(100).joined(separator: ", "))")
        }
        var user = "<context>\n\(context.joined(separator: "\n"))\n</context>\n\n"
        if let selectedText {
            user += "<selected_text>\n\(selectedText)\n</selected_text>\n\n"
        }
        user += "<instruction>\n\(instruction)\n</instruction>"

        var messages: [[String: Any]] = [["role": "user", "content": user]]

        for _ in 0..<Self.maxTurns {
            let response = try await client.send([
                "max_tokens": 16000,
                "system": Self.system,
                "tools": Self.tools,
                "output_config": ["effort": "low"],
                "messages": messages,
            ])
            let content = response["content"] as? [[String: Any]] ?? []
            let stopReason = response["stop_reason"] as? String
            // Append the full content unchanged (thinking blocks included).
            messages.append(["role": "assistant", "content": content])

            let toolUses = content.filter { $0["type"] as? String == "tool_use" }
            guard stopReason == "tool_use", !toolUses.isEmpty else {
                let text = ClaudeClient.text(of: response).trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? "Done." : text
            }

            var results: [[String: Any]] = []
            for use in toolUses {
                let id = use["id"] as? String ?? ""
                let name = use["name"] as? String ?? ""
                let input = use["input"] as? [String: Any] ?? [:]
                onStep(Self.describe(name, input))
                let result = await execute(name, input)
                var block: [String: Any] = ["type": "tool_result", "tool_use_id": id, "content": result.message]
                if result.isError { block["is_error"] = true }
                results.append(block)
            }
            // All results for this turn go back in a single user message.
            messages.append(["role": "user", "content": results])
        }
        return "Stopped after \(Self.maxTurns) steps."
    }

    private func execute(_ name: String, _ input: [String: Any]) async -> ActionResult {
        func str(_ key: String) -> String { input[key] as? String ?? "" }
        switch name {
        case "open_app": return await MacActions.openApp(str("name"))
        case "quit_app": return MacActions.quitApp(str("name"))
        case "open_url": return MacActions.openURL(str("url"))
        case "web_search": return MacActions.webSearch(str("query"))
        case "type_text": return MacActions.typeText(str("text"))
        case "press_shortcut": return MacActions.pressShortcut(str("keys"))
        case "set_volume": return MacActions.setVolume(input["percent"] as? Int ?? 50)
        case "media_control": return MacActions.media(str("action"))
        case "system_action": return await MacActions.system(str("action"))
        case "create_reminder": return MacActions.createReminder(title: str("title"), due: str("due"))
        case "create_note": return MacActions.createNote(title: str("title"), body: str("body"))
        case "run_shortcut": return await MacActions.runShortcut(str("name"), input: str("input"))
        case "run_command": return await MacActions.runCommand(str("command"), purpose: str("purpose"))
        default: return .fail("Unknown tool \(name)")
        }
    }

    private static func describe(_ name: String, _ input: [String: Any]) -> String {
        func str(_ key: String) -> String { input[key] as? String ?? "" }
        switch name {
        case "open_app": return "Opening \(str("name"))…"
        case "quit_app": return "Quitting \(str("name"))…"
        case "open_url": return "Opening \(str("url"))…"
        case "web_search": return "Searching for \(str("query"))…"
        case "type_text": return "Typing…"
        case "press_shortcut": return "Pressing \(str("keys"))…"
        case "set_volume": return "Setting volume…"
        case "media_control": return "Controlling playback…"
        case "system_action": return "Running \(str("action").replacingOccurrences(of: "_", with: " "))…"
        case "create_reminder": return "Adding reminder…"
        case "create_note": return "Creating note…"
        case "run_shortcut": return "Running shortcut \(str("name"))…"
        case "run_command": return "Waiting for you to confirm…"
        default: return "Working…"
        }
    }

    // MARK: Tool definitions

    private static func tool(_ name: String, _ description: String, _ properties: [String: Any]) -> [String: Any] {
        [
            "name": name,
            "description": description,
            "strict": true,
            "input_schema": [
                "type": "object",
                "properties": properties,
                "required": Array(properties.keys).sorted(),
                "additionalProperties": false,
            ],
        ]
    }

    private static func string(_ description: String) -> [String: Any] {
        ["type": "string", "description": description]
    }

    private static func enumeration(_ values: [String], _ description: String) -> [String: Any] {
        ["type": "string", "enum": values, "description": description]
    }

    static let tools: [[String: Any]] = [
        tool("open_app", "Open or switch to an application by name, e.g. \"Safari\", \"Slack\", \"System Settings\".",
             ["name": string("Application name as shown in Finder, without .app")]),
        tool("quit_app", "Quit a running application by name.",
             ["name": string("Application name")]),
        tool("open_url", "Open a web page in the default browser.",
             ["url": string("Full URL or domain, e.g. https://github.com or github.com")]),
        tool("web_search", "Search the web in the default browser.",
             ["query": string("Search query")]),
        tool("type_text", "Insert text at the cursor in the frontmost app, replacing the current selection if there is one. Use it to write new text or to replace selected text with a rewritten version.",
             ["text": string("Exact text to insert")]),
        tool("press_shortcut", "Press a keyboard shortcut in the frontmost app, e.g. \"cmd+t\" for a new tab, \"cmd+shift+n\", \"return\", \"escape\". Modifiers: cmd, shift, opt, ctrl.",
             ["keys": string("Shortcut such as cmd+shift+t")]),
        tool("set_volume", "Set the system output volume.",
             ["percent": ["type": "integer", "description": "Volume from 0 to 100"]]),
        tool("media_control", "Control whatever media is playing (Music, Spotify, a browser video).",
             ["action": enumeration(["play_pause", "next", "previous"], "Playback action")]),
        tool("system_action", "Run a system action.",
             ["action": enumeration(["toggle_dark_mode", "lock_screen", "sleep_display", "show_desktop"], "System action")]),
        tool("create_reminder", "Add a reminder to Apple Reminders.",
             ["title": string("What to be reminded about"),
              "due": string("Local date and time as yyyy-MM-ddTHH:mm, or an empty string for no due date")]),
        tool("create_note", "Create a note in Apple Notes.",
             ["title": string("Note title"), "body": string("Note text; use newlines between lines")]),
        tool("run_shortcut", "Run one of the user's Apple Shortcuts by its exact name.",
             ["name": string("Exact shortcut name from the context list"),
              "input": string("Text to pass to the shortcut as input, or an empty string")]),
        tool("run_command", "Run a shell command or script in the user's Terminal (zsh). The user sees the exact command and must click Run before it executes, so send one complete command (chain steps with &&). Use for scripts, git, builds, package managers, and anything a developer would type in Terminal.",
             ["command": string("The exact zsh command to run"),
              "purpose": string("A few words on what it does, shown to the user")]),
    ]
}
