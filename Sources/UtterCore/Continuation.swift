import Foundation

/// Fits a dictation into the text already around the cursor: capitalisation,
/// spacing and the final full stop.
///
/// - At the start of a field, a line or a sentence: capital letter.
/// - Mid-sentence: lower-case first word (unless it's a name, "I", or an
///   acronym), and a space if the previous character isn't one.
/// - If text continues right after the cursor in lower case, the dictation's
///   own full stop is dropped and a space is added.
public enum ContinuationFormatter {
    static let openers = Set("([{\"'“‘-/\t")

    /// `keepCapital(word)` says whether a word must stay capitalised (a name).
    public static func adapt(_ text: String, before: String, after: String,
                             keepCapital: (String) -> Bool = { _ in false }) -> String {
        var out = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !out.isEmpty else { return out }
        let startsLine = out.first == "•" || out.hasPrefix("\n")

        let last = before.last
        let lastVisible = before.last(where: { !$0.isWhitespace })
        let atStart = before.trimmingCharacters(in: .whitespaces).isEmpty || last == "\n"
        let afterSentence = lastVisible.map { ".!?".contains($0) } ?? true
        let midSentence = !atStart && !afterSentence && (lastVisible.map { $0.isLetter || $0.isNumber || ",;:".contains($0) } ?? false)

        if atStart || afterSentence || startsLine {
            out = capitalizeFirst(out)
        } else if midSentence {
            out = lowercaseFirstWord(out, keepCapital: keepCapital)
        }
        if let last, !atStart, !last.isWhitespace, !openers.contains(last), !startsLine {
            out = " " + out
        }

        if let next = after.first, !next.isWhitespace {
            if next.isLetter, next.isLowercase, out.hasSuffix(".") { out.removeLast() }
            if next.isLetter || next.isNumber { out += " " }
        }
        return out
    }

    static func capitalizeFirst(_ text: String) -> String {
        guard let i = text.firstIndex(where: { $0.isLetter }) else { return text }
        return text.replacingCharacters(in: i...i, with: text[i].uppercased())
    }

    static func lowercaseFirstWord(_ text: String, keepCapital: (String) -> Bool) -> String {
        let word = String(text.prefix(while: { $0.isLetter || $0 == "'" || $0 == "’" }))
        guard let first = word.first, first.isUppercase else { return text }
        if word == "I" || word.hasPrefix("I'") || word.hasPrefix("I’") { return text }
        if word.count >= 2, word == word.uppercased() { return text } // acronym: API, NASA
        if keepCapital(word) { return text }
        return first.lowercased() + text.dropFirst()
    }
}

/// Spots words the user corrected right after a dictation, so they can be
/// added to the personal dictionary.
public enum CorrectionFinder {
    public struct Correction: Equatable, Sendable {
        public var from: String
        public var to: String

        public init(from: String, to: String) {
            self.from = from
            self.to = to
        }
    }

    /// Single-word replacements between `before` and `after` (the field's text
    /// right after inserting, and later) where the old word came from the
    /// dictation and the new one looks like a fix of it, not a rewrite.
    public static func corrections(before: String, after: String, inserted: String) -> [Correction] {
        let a = tokens(before), b = tokens(after)
        guard a.count < 3000, b.count < 3000 else { return [] }
        let dictated = Set(tokens(inserted).map { $0.lowercased() })
        var found: [Correction] = []
        for (old, new) in replacements(a, b) where old.count == 1 && new.count == 1 {
            let from = old[0], to = new[0]
            guard dictated.contains(from.lowercased()), from != to, to.count >= 2,
                  to.allSatisfy({ $0.isLetter || $0.isNumber || "-'’".contains($0) }) else { continue }
            let distance = editDistance(from.lowercased(), to.lowercased())
            let similar = distance <= max(2, max(from.count, to.count) / 2) || from.lowercased() == to.lowercased()
            if similar, !found.contains(Correction(from: from, to: to)) { found.append(Correction(from: from, to: to)) }
        }
        return found
    }

    static func tokens(_ text: String) -> [String] {
        text.split { !($0.isLetter || $0.isNumber || "-'’".contains($0)) }.map(String.init)
    }

    /// Replaced runs (old words, new words) from a longest-common-subsequence diff.
    static func replacements(_ a: [String], _ b: [String]) -> [([String], [String])] {
        let n = a.count, m = b.count
        var lcs = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        var out: [([String], [String])] = []
        var i = 0, j = 0
        var old: [String] = [], new: [String] = []
        func flush() {
            if !old.isEmpty || !new.isEmpty { out.append((old, new)) }
            old = []; new = []
        }
        while i < n || j < m {
            if i < n, j < m, a[i] == b[j] {
                flush(); i += 1; j += 1
            } else if j < m, i == n || lcs[i][j + 1] >= lcs[i + 1][j] {
                new.append(b[j]); j += 1
            } else {
                old.append(a[i]); i += 1
            }
        }
        flush()
        return out
    }

    static func editDistance(_ s: String, _ t: String) -> Int {
        let a = Array(s), b = Array(t)
        var row = Array(0...b.count)
        for i in 1...max(1, a.count) where !a.isEmpty {
            var prev = row[0]
            row[0] = i
            for j in 1...max(1, b.count) where !b.isEmpty {
                let current = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, prev + (a[i - 1] == b[j - 1] ? 0 : 1))
                prev = current
            }
        }
        return a.isEmpty ? b.count : (b.isEmpty ? a.count : row[b.count])
    }
}
