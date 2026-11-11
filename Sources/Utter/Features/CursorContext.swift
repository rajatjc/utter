import UtterCore
import AppKit
import ApplicationServices
import NaturalLanguage

/// The text right around the cursor in the focused field, read through
/// Accessibility when the app supports it (most native apps, many others).
struct CursorContext {
    /// Up to ~300 characters before the cursor (or the selection being replaced).
    var before: String
    /// Up to ~100 characters after it.
    var after: String
    /// Where the cursor is, as a character offset in the field.
    var location: Int
    /// The field, for watching later edits.
    var element: AXUIElement?

    @MainActor
    static func capture() -> CursorContext? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused else { return nil }
        let element = focused as! AXUIElement

        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeRef else { return nil }
        var selection = CFRange()
        guard AXValueGetValue(rangeRef as! AXValue, .cfRange, &selection) else { return nil }

        var countRef: CFTypeRef?
        var total = Int.max
        if AXUIElementCopyAttributeValue(element, kAXNumberOfCharactersAttribute as CFString, &countRef) == .success,
           let n = countRef as? Int { total = n }

        let beforeStart = max(0, selection.location - 300)
        let before = string(element, CFRange(location: beforeStart, length: selection.location - beforeStart)) ?? ""
        let afterStart = selection.location + selection.length
        let afterLength = max(0, min(100, total == .max ? 100 : total - afterStart))
        let after = afterLength > 0 ? (string(element, CFRange(location: afterStart, length: afterLength)) ?? "") : ""
        return CursorContext(before: before, after: after, location: selection.location, element: element)
    }

    /// The text in `range`, via the parameterized attribute (no need to read a huge document).
    static func string(_ element: AXUIElement, _ range: CFRange) -> String? {
        guard range.length > 0 else { return "" }
        var r = range
        guard let value = AXValueCreate(.cfRange, &r) else { return nil }
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString,
                                                         value, &result) == .success else { return nil }
        return result as? String
    }

    /// The whole field's text, if it's not too large.
    static func value(of element: AXUIElement) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &v) == .success,
              let text = v as? String, text.count < 200_000 else { return nil }
        return text
    }

    /// Fits `text` into this context (capitalisation, spacing, final full stop).
    func fit(_ text: String) -> String {
        let names = Set(Prefs.dictionaryWords.map { $0.lowercased() })
        let detected = Self.properNames(in: text)
        return ContinuationFormatter.adapt(text, before: before, after: after) { word in
            names.contains(word.lowercased()) || detected.contains(word)
        }
    }

    /// Words NaturalLanguage tags as names of people, places or organisations.
    static func properNames(in text: String) -> Set<String> {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var names = Set<String>()
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType,
                             options: [.omitWhitespace, .omitPunctuation, .joinNames]) { tag, range in
            if let tag, [.personalName, .placeName, .organizationName].contains(tag) {
                text[range].split(separator: " ").forEach { names.insert(String($0)) }
            }
            return true
        }
        return names
    }
}
