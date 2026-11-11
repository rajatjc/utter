import Foundation

/// Joins the texts of consecutive Whisper chunks into one transcript.
///
/// Whisper ends every chunk as if it were a complete sentence, so a pause in
/// the middle of a sentence becomes a full stop: "…two open roles. And we
/// have five candidates…". When a chunk ends with a full stop and the next
/// begins with a word that usually continues a sentence, the two are joined
/// with a comma instead.
public enum ChunkJoiner {
    /// Marks a stretch with no speech between chunks (a long pause or noise
    /// that wasn't sent). Chunks on either side are never merged across it.
    public static let hardBreak = "\u{2029}"

    /// Words that, capitalised after a seam, almost always continue the sentence.
    static let continuations: Set<String> = [
        "and", "so", "but", "or", "because", "which", "who", "where", "while",
        "although", "though", "unless", "until", "then", "plus",
    ]

    public static func join(_ chunks: [String]) -> String {
        var result = ""
        var afterBreak = false
        for raw in chunks {
            if raw == hardBreak { afterBreak = true; continue }
            let chunk = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !chunk.isEmpty else { continue }
            defer { afterBreak = false }
            guard !result.isEmpty else { result = chunk; continue }
            if !afterBreak, result.hasSuffix("."), !result.hasSuffix("..."), continuesSentence(chunk) {
                result.removeLast()
                result += ", " + lowercasedFirstWord(chunk)
            } else if endsSentence(result) {
                // A new sentence after a full stop starts with a capital.
                result += " " + capitalizedFirstLetter(chunk)
            } else if startsNewSentence(chunk) {
                // Whisper dropped the full stop at the end of the previous chunk.
                result += ". " + chunk
            } else {
                result += " " + chunk
            }
        }
        return result
    }

    static func continuesSentence(_ text: String) -> Bool {
        guard let first = text.split(whereSeparator: { $0 == " " || $0 == "," }).first,
              first.first?.isUppercase == true else { return false }
        return continuations.contains(first.lowercased())
    }

    static func endsSentence(_ text: String) -> Bool {
        guard let last = text.last else { return false }
        return ".!?".contains(last)
    }

    /// Starts with a capitalised word other than "I" (and its contractions),
    /// which mid-sentence would be unusual.
    static func startsNewSentence(_ text: String) -> Bool {
        guard let first = text.split(separator: " ").first, first.first?.isUppercase == true else { return false }
        let word = first.lowercased().filter { $0.isLetter || $0 == "'" || $0 == "’" }
        return !(word == "i" || word.hasPrefix("i'") || word.hasPrefix("i’"))
    }

    static func capitalizedFirstLetter(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    static func lowercasedFirstWord(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.lowercased() + text.dropFirst()
    }
}
