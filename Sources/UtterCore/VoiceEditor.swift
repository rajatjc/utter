import Foundation

/// Spoken editing commands inside a dictation, applied before cleanup:
///
/// - "scratch that" / "delete that" / "strike that": removes what was just
///   said. Said on its own, it asks to undo the previous dictation.
/// - "new paragraph" / "new line" (or "next line"): inserts the break.
/// - "make that a list" / "make this a list" / "bullet that" at the end:
///   turns what was said into bullet points.
public enum VoiceEditor {
    public struct Result: Equatable, Sendable {
        public var text: String
        /// The whole dictation was "scratch that": undo the previous one.
        public var undoPrevious: Bool

        public init(text: String, undoPrevious: Bool) {
            self.text = text
            self.undoPrevious = undoPrevious
        }
    }

    static let fillers: Set<String> = ["actually", "no", "sorry", "wait", "oh", "oops", "um", "uh", "okay", "ok", "so"]

    public static func apply(_ transcript: String) -> Result {
        var text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if isOnly(text, pattern: scratch) { return Result(text: "", undoPrevious: true) }

        text = applyScratches(text)
        var makeList = false
        if let range = text.range(of: listCommand, options: [.regularExpression, .caseInsensitive]) {
            makeList = true
            text = String(text[..<range.lowerBound])
        }
        text = applyBreaks(text)
        if makeList { text = bulletList(text) }
        return Result(text: text.trimmingCharacters(in: .whitespacesAndNewlines), undoPrevious: false)
    }

    // MARK: Scratch that

    static let scratch = #"\b(scratch|delete|strike) (that|this)\b"#

    static func isOnly(_ text: String, pattern: String) -> Bool {
        let stripped = text.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
        return stripped.range(of: "^" + pattern + "$", options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func applyScratches(_ input: String) -> String {
        var text = input
        while let range = text.range(of: scratch, options: [.regularExpression, .caseInsensitive]) {
            var before = String(text[..<range.lowerBound])
            var after = String(text[range.upperBound...])
            after = String(after.drop(while: { ",.!? ".contains($0) }))
            before = removeLastUtterance(before)
            if !before.isEmpty, !after.isEmpty { before += " " }
            text = before + capitalizedIfSentenceStart(after, previous: before)
        }
        return text
    }

    /// Removes the phrase spoken just before "scratch that". If that phrase is
    /// only a filler ("Actually, scratch that"), the sentence before it goes too.
    static func removeLastUtterance(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
        let (head, fragment) = splitLastSentence(trimmed)
        let words = fragment.lowercased().split { !$0.isLetter && $0 != "'" }.map(String.init)
        let onlyFillers = !words.isEmpty && words.allSatisfy { fillers.contains($0) }
        if onlyFillers || words.isEmpty {
            // Drop the filler and the full sentence before it.
            let body = head.trimmingCharacters(in: .whitespaces)
            let withoutStop = body.hasSuffix(".") || body.hasSuffix("!") || body.hasSuffix("?") ? String(body.dropLast()) : body
            return splitLastSentence(withoutStop).head.trimmingCharacters(in: .whitespaces)
        }
        return head.trimmingCharacters(in: .whitespaces)
    }

    /// (text up to and including the last sentence end, the unfinished part after it)
    static func splitLastSentence(_ text: String) -> (head: String, fragment: String) {
        guard let index = text.lastIndex(where: { ".!?\n".contains($0) }) else { return ("", text) }
        let head = String(text[...index])
        let fragment = String(text[text.index(after: index)...]).trimmingCharacters(in: .whitespaces)
        return (head, fragment)
    }

    static func capitalizedIfSentenceStart(_ text: String, previous: String) -> String {
        let prev = previous.trimmingCharacters(in: .whitespaces)
        guard prev.isEmpty || ".!?\n".contains(prev.last!), let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    // MARK: New line / new paragraph

    static func applyBreaks(_ input: String) -> String {
        var text = input
        for (pattern, replacement) in [(#"\bnew paragraph\b"#, "\n\n"), (#"\b(new|next) line\b"#, "\n")] {
            // Eat spaces and commas before the command (but keep a full stop that
            // ended the previous sentence), and any punctuation the recognizer added after it.
            let regex = try! NSRegularExpression(pattern: #"[ ,;]*"# + pattern + #"[ ,.;:]*"#, options: .caseInsensitive)
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: replacement)
        }
        // A new line starts with a capital.
        var out = ""
        var capitalizeNext = false
        for ch in text {
            if capitalizeNext, ch.isLetter {
                out += ch.uppercased()
                capitalizeNext = false
                continue
            }
            if ch == "\n" { capitalizeNext = true } else if !ch.isWhitespace { capitalizeNext = false }
            out.append(ch)
        }
        return out
    }

    // MARK: Make that a list

    static let listCommand = #"[ ,.;]*\b(make (that|this|it) (a|into a) (bulleted |bullet )?list|bullet (that|this)|as a (bulleted |bullet )?list)\b[ ,.!]*$"#

    static func bulletList(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var intro = ""
        var body = trimmed
        if let colon = trimmed.firstIndex(of: ":") {
            intro = String(trimmed[...colon])
            body = String(trimmed[trimmed.index(after: colon)...])
        }
        var items = sentences(body)
        if items.count < 2 {
            items = body.components(separatedBy: CharacterSet(charactersIn: ",;"))
                .flatMap { $0.components(separatedBy: " and ") }
        }
        let cleaned = items
            .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,;"))) }
            .map { $0.lowercased().hasPrefix("and ") ? String($0.dropFirst(4)) : $0 }
            .filter { !$0.isEmpty }
            .map { "• " + ($0.first!.uppercased() + $0.dropFirst()) }
        guard cleaned.count >= 2 else { return trimmed }
        return (intro.isEmpty ? "" : intro + "\n") + cleaned.joined(separator: "\n")
    }

    static func sentences(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        for ch in text {
            current.append(ch)
            if ".!?\n".contains(ch) {
                out.append(current)
                current = ""
            }
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty { out.append(current) }
        return out
    }
}
