// `swift run UtterChecks` — checks UtterCore's logic without XCTest or
// swift-testing (both need full Xcode). Exits non-zero on any failure.
import Foundation
import UtterCore

var failures = 0
var checks = 0

func check(_ condition: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
    checks += 1
    if !condition {
        failures += 1
        print("✗ \(name)\(detail().isEmpty ? "" : ": \(detail())")")
    }
}

// MARK: Snippets and dictionary

let snippets = Snippet.parse("""
my email => you@example.com
  cal link =>  https://cal.com/x?a=>b
no arrow here
 => empty trigger
""")
check(snippets.count == 2, "snippet parse skips bad lines", "\(snippets)")
check(snippets.first == Snippet(trigger: "my email", expansion: "you@example.com"), "snippet trims")
check(snippets.last?.expansion == "https://cal.com/x?a=>b", "snippet keeps => in expansion")
check(Snippet.expand("send it to My Email", with: snippets) == "send it to you@example.com", "expand is case-insensitive")
check(PersonalDictionary.parse("Acme\n\n  Ada Lovelace \n") == ["Acme", "Ada Lovelace"], "dictionary parse")

// MARK: Basic cleanup

check(BasicCleaner.clean("um so uh we ship today") == "So we ship today", "fillers removed and capitalised",
      BasicCleaner.clean("um so uh we ship today"))
check(BasicCleaner.clean("") == "", "empty stays empty")
check(BasicCleaner.clean("email my email", snippets: snippets) == "Email you@example.com", "basic clean expands snippets")

// MARK: Cleanup guard

check(CleanupGuard.looksLikeCleanup(of: "um what time does the store close", output: "What time does the store close?"),
      "guard accepts a real cleanup")
check(!CleanupGuard.looksLikeCleanup(of: "what's the capital of france", output: "Paris."),
      "guard rejects an answer")
check(CleanupGuard.looksLikeCleanup(of: "ask acme team", output: "Ask Acme team.", knownWords: ["Acme"]),
      "guard allows dictionary words")
check(!CleanupGuard.looksLikeCleanup(of: "hello", output: ""), "guard rejects empty output")

// MARK: Pause stitching (recorded behaviour of Apple's recognizer)

var stitcher = SegmentStitcher()
for partial in ["The", "The first part", "The first part is about the quarterly roadmap",
                "And", "And the second part", "And the second part comes after a long pause"] {
    stitcher.update(partial)
}
check(stitcher.text == "The first part is about the quarterly roadmap And the second part comes after a long pause",
      "stitcher keeps text across a restart", stitcher.text)
var refined = SegmentStitcher()
refined.update("And this second")
refined.update("And the second") // recognizer revising a word, not restarting
check(refined.text == "And the second", "stitcher doesn't split on revisions", refined.text)
var committedThenNew = SegmentStitcher()
committedThenNew.update("first segment")
committedThenNew.commit()
committedThenNew.update("second")
check(committedThenNew.text == "first segment second", "stitcher joins committed segments")

// MARK: Hotkey state machine

let start = Date(timeIntervalSince1970: 1_000)
func at(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }
let chords: (Mode) -> HotkeyChord = { $0 == .dictation ? .leftControlOption : .rightCommand }
let dictation = HotkeyChord.leftControlOption.mask
let command = HotkeyChord.rightCommand.mask

var hk = ChordStateMachine()
check(hk.flagsChanged(held: 0x01, chords: chords, at: at(0)) == [], "half a chord does nothing")
check(hk.flagsChanged(held: dictation, chords: chords, at: at(0.05)) == [.press(.dictation)], "full chord presses")
check(hk.flagsChanged(held: 0, chords: chords, at: at(1.0)) == [.release(.dictation)], "release after a hold")

hk = ChordStateMachine()
_ = hk.flagsChanged(held: dictation, chords: chords, at: at(0))
check(hk.flagsChanged(held: 0, chords: chords, at: at(0.1)) == [.cancel], "a short tap cancels")
_ = hk.flagsChanged(held: dictation, chords: chords, at: at(0.3))
check(hk.flagsChanged(held: 0, chords: chords, at: at(0.4)) == [.lock(.dictation)], "double tap locks hands-free")
check(hk.isLocked, "locked after double tap")
check(hk.flagsChanged(held: dictation, chords: chords, at: at(5)) == [.release(.dictation)], "press while locked finishes")
check(hk.flagsChanged(held: 0, chords: chords, at: at(5.1)) == [], "the finishing key-up is ignored")

hk = ChordStateMachine()
_ = hk.flagsChanged(held: command, chords: chords, at: at(0))
check(hk.keyDown(isEscape: false) == [.cancel], "typing while holding cancels (a shortcut)")
check(hk.flagsChanged(held: 0, chords: chords, at: at(1)) == [], "release after a cancel is ignored")

hk = ChordStateMachine()
_ = hk.flagsChanged(held: command, chords: chords, at: at(0))
check(hk.flagsChanged(held: command | 0x02, chords: chords, at: at(0.5)) == [.cancel], "extra modifier cancels")

hk = ChordStateMachine()
check(hk.flagsChanged(held: dictation | 0x02, chords: chords, at: at(0)) == [], "chord plus extra modifier doesn't start")

hk = ChordStateMachine()
hk.beginExternal(.dictation)
check(hk.keyDown(isEscape: false) == [], "typing doesn't cancel a clicked session")
check(hk.keyDown(isEscape: true) == [.cancel], "Esc cancels a clicked session")

// MARK: Shortcuts

check(ShortcutParser.parse("cmd+shift+t") == {
    var s = ShortcutParser.Shortcut(keyCode: 0x11); s.command = true; s.shift = true; return s
}(), "parse cmd+shift+t")
check(ShortcutParser.parse("Escape")?.keyCode == 0x35, "parse escape")
check(ShortcutParser.parse("f12")?.keyCode == 0x6F, "parse f12")
check(ShortcutParser.parse("hyper+k") == nil, "unknown modifier rejected")
check(ShortcutParser.parse("cmd+nope") == nil, "unknown key rejected")

print(failures == 0 ? "✓ all \(checks) checks passed" : "\(failures) of \(checks) checks failed")
exit(failures == 0 ? 0 : 1)
