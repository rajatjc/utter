import Foundation

/// The two ways of talking to Utter.
public enum Mode: String, Codable, Sendable {
    case dictation
    case command
}

/// A spoken phrase that expands into longer text, e.g. "my email" → an address.
public struct Snippet: Equatable, Sendable {
    public var trigger: String
    public var expansion: String

    public init(trigger: String, expansion: String) {
        self.trigger = trigger
        self.expansion = expansion
    }

    /// Parses lines of the form `trigger => expansion`. Lines without `=>` or
    /// with an empty trigger are skipped; `=>` inside the expansion is kept.
    public static func parse(_ text: String) -> [Snippet] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.components(separatedBy: "=>")
            guard parts.count >= 2 else { return nil }
            let trigger = parts[0].trimmingCharacters(in: .whitespaces)
            let expansion = parts.dropFirst().joined(separator: "=>").trimmingCharacters(in: .whitespaces)
            return trigger.isEmpty ? nil : Snippet(trigger: trigger, expansion: expansion)
        }
    }

    /// Replaces every trigger (case-insensitive) with its expansion.
    public static func expand(_ text: String, with snippets: [Snippet]) -> String {
        snippets.reduce(text) { result, snippet in
            result.replacingOccurrences(of: snippet.trigger, with: snippet.expansion, options: .caseInsensitive)
        }
    }
}

/// The personal dictionary: one word or name per line.
public enum PersonalDictionary {
    public static func parse(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

/// Offline cleanup used when no AI model is available or the model's output is rejected.
public enum BasicCleaner {
    public static func clean(_ transcript: String, snippets: [Snippet] = []) -> String {
        var text = transcript
        for pattern in ["\\bum+\\b,?", "\\buh+\\b,?", "\\berm\\b,?", "\\bhmm+\\b,?"] {
            text = text.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        text = text.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        text = Snippet.expand(text, with: snippets)
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}

/// Small models sometimes answer a dictated question ("what's the capital of
/// France" → "Paris.") instead of cleaning it up. A real cleanup keeps the
/// speaker's words, so most output words must appear in the transcript.
public enum CleanupGuard {
    public static func looksLikeCleanup(of input: String, output: String, knownWords: [String] = [],
                                        threshold: Double = 0.75) -> Bool {
        let inputWords = Set(tokens(input)).union(knownWords.flatMap(tokens))
        let outputWords = tokens(output)
        guard !outputWords.isEmpty else { return false }
        let kept = outputWords.filter { inputWords.contains($0) }.count
        return Double(kept) / Double(outputWords.count) >= threshold
    }

    static func tokens(_ s: String) -> [String] {
        s.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}

/// Apple's recognizer silently restarts its transcription after a pause, so the
/// next partial result no longer includes earlier words. This keeps finished
/// segments and stitches them to the current one.
public struct SegmentStitcher: Sendable {
    public private(set) var committed: [String] = []
    public private(set) var current = ""

    public init() {}

    public var text: String {
        (committed + [current]).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Feeds the recognizer's latest partial text.
    public mutating func update(_ newText: String) {
        // Much shorter and not a trimmed version of what we had: a new utterance began.
        if !current.isEmpty, newText.count < current.count / 2, !current.hasPrefix(newText) {
            commit()
        }
        current = newText
    }

    /// The recognizer finished a segment (final result or error).
    public mutating func commit() {
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { committed.append(trimmed) }
        current = ""
    }
}
