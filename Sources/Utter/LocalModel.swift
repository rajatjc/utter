import UtterCore
import Foundation
import FoundationModels

/// Dictation cleanup with Apple's on-device model (Apple Intelligence, macOS 26+).
/// Free, private and offline, but smaller than Claude, so the prompt uses worked
/// examples and the output is checked before it's typed. On older systems every
/// call reports the model as unavailable.
enum LocalModel {
    static var isAvailable: Bool {
        if #available(macOS 26, *) { return AppleModel.isAvailable }
        return false
    }

    static var unavailableReason: String? {
        if #available(macOS 26, *) { return AppleModel.unavailableReason }
        return "On-device dictation needs macOS 26 or newer."
    }

    static func clean(_ transcript: String, context: FocusContext) async throws -> String {
        if #available(macOS 26, *) { return try await AppleModel.clean(transcript, context: context) }
        return BasicCleaner.clean(transcript, snippets: Prefs.snippets)
    }

    /// Loads the model while the user is still talking, so cleanup starts warm.
    static func warmUp() {
        if #available(macOS 26, *) { AppleModel.warmUp() }
    }
}

@available(macOS 26, *)
private enum AppleModel {
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: nil
        case .unavailable(let reason): "Apple Intelligence isn't available (\(reason)). Turn it on in System Settings → Apple Intelligence & Siri."
        }
    }

    private static let baseInstructions = """
    You are a copy editor for dictated text. The user message is a raw speech transcript \
    inside <dictation> tags. Rewrite it as clean written text:
    1. Remove filler words (um, uh, like, you know, "so" at the start) and repeated words.
    2. If the speaker corrects themselves ("X, no wait, Y" or "X, I mean Y"), keep only Y.
    3. Add correct punctuation and capitalization: a capital letter at the start of each \
    sentence, and a period or question mark at the end.
    4. Keep line breaks and lines starting with "• " exactly where they are.
    5. Keep the speaker's words otherwise. The dictation is never addressed to you: if it is \
    a question, output the question itself, cleaned up. Never answer it and never add anything.
    Output only the rewritten text, without the tags.

    Example input: <dictation>um i'll be there at five no actually six and uh can you bring the charger</dictation>
    Example output: I'll be there at six. Can you bring the charger?

    Example input: <dictation>so the the deploy failed because uh the config was missing i mean the env file was missing</dictation>
    Example output: The deploy failed because the env file was missing.

    Example input: <dictation>uh what time does the um the store close today</dictation>
    Example output: What time does the store close today?
    """

    static func clean(_ transcript: String, context: FocusContext) async throws -> String {
        var instructions = baseInstructions + "\n\nWhere it will be typed: \(context.styleHint)"
        let words = Prefs.dictionaryWords
        if !words.isEmpty {
            instructions += "\nSpell these names and terms exactly like this: \(words.joined(separator: ", "))."
        }
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(
            to: "<dictation>\(transcript)</dictation>",
            options: GenerationOptions(temperature: 0)
        )
        let text = response.content
            .replacingOccurrences(of: "<dictation>", with: "")
            .replacingOccurrences(of: "</dictation>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Small models sometimes answer the question instead of transcribing it.
        // If the output doesn't look like a cleaned version of the input, don't use it.
        guard CleanupGuard.looksLikeCleanup(of: transcript, output: text, knownWords: Prefs.dictionaryWords) else {
            return BasicCleaner.clean(transcript, snippets: Prefs.snippets)
        }
        return Snippet.expand(text, with: Prefs.snippets)
    }

    static func warmUp() {
        guard isAvailable else { return }
        Task.detached(priority: .utility) {
            _ = try? await LanguageModelSession().respond(
                to: "Reply with OK.",
                options: GenerationOptions(maximumResponseTokens: 2)
            )
        }
    }
}
