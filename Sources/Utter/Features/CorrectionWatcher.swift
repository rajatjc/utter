import UtterCore
import AppKit
import ApplicationServices

/// After a dictation is typed, watches the field for about 40 seconds. If the
/// user fixes a word Utter got wrong ("cubernetes" → "Kubernetes"), it offers
/// to add the fixed word to the personal dictionary, so Whisper and the cleanup
/// spell it right next time.
@MainActor
final class CorrectionWatcher {
    static let shared = CorrectionWatcher()

    private var timer: Timer?
    private var element: AXUIElement?
    private var baseline = ""
    private var inserted = ""
    private var window: Range<Int> = 0..<0
    private var ticks = 0
    private var offered = Set<String>()

    var onSuggestion: ((String) -> Void)?

    /// Call right after inserting `text` at `context.location`.
    func watch(_ text: String, context: CursorContext?) {
        stop()
        guard Prefs.learnFromCorrections, let context, let element = context.element else { return }
        self.element = element
        inserted = text
        ticks = 0
        // Give the paste a moment to land, then remember what the field looks like.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, let value = CursorContext.value(of: element) else { return }
            let start = max(0, context.location - 200)
            self.window = start..<min(value.count, context.location + text.count + 200)
            self.baseline = Self.slice(value, self.window)
            self.timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.check(lengthBefore: value.count) }
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        element = nil
    }

    private func check(lengthBefore: Int) {
        ticks += 1
        guard ticks <= 20, let element, let value = CursorContext.value(of: element) else { return stop() }
        // Grow the window by however much the field changed in length.
        let delta = value.count - lengthBefore
        let current = Self.slice(value, window.lowerBound..<max(window.lowerBound, window.upperBound + delta))
        guard current != baseline else { return }
        let dictionary = Set(Prefs.dictionaryWords.map { $0.lowercased() })
        let declined = Prefs.declinedWords
        for fix in CorrectionFinder.corrections(before: baseline, after: current, inserted: inserted) {
            let word = fix.to
            guard !dictionary.contains(word.lowercased()), !declined.contains(word.lowercased()),
                  !offered.contains(word.lowercased()), Self.worthLearning(word) else { continue }
            offered.insert(word.lowercased())
            onSuggestion?(word)
            stop()
            return
        }
    }

    /// Names, jargon and anything the system dictionary doesn't know. Fixes
    /// between ordinary words ("their" → "there") aren't worth a dictionary entry.
    static func worthLearning(_ word: String) -> Bool {
        if word.first?.isUppercase == true { return true }
        let checker = NSSpellChecker.shared
        let range = checker.checkSpelling(of: word, startingAt: 0)
        return range.location != NSNotFound
    }

    static func slice(_ text: String, _ range: Range<Int>) -> String {
        let lower = max(0, min(range.lowerBound, text.count))
        let upper = max(lower, min(range.upperBound, text.count))
        let start = text.index(text.startIndex, offsetBy: lower)
        let end = text.index(text.startIndex, offsetBy: upper)
        return String(text[start..<end])
    }
}
