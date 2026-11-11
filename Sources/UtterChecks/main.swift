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

// MARK: Notch position on any display size and arrangement

// This MacBook (14", default scaling): 1728 pt wide, 771.5 pt either side.
var notch = NotchLayout.notch(frameMinX: 0, frameWidth: 1728, leftWidth: 771.5, rightWidth: 771.5)
check(notch.centerX == 864 && notch.width == 185, "14-inch at the origin", "\(notch)")
// Same MacBook arranged to the right of a 2560 pt external display.
notch = NotchLayout.notch(frameMinX: 2560, frameWidth: 1728, leftWidth: 771.5, rightWidth: 771.5)
check(notch.centerX == 2560 + 864, "MacBook right of an external display", "\(notch)")
// Arranged to the left (negative x).
notch = NotchLayout.notch(frameMinX: -1728, frameWidth: 1728, leftWidth: 771.5, rightWidth: 771.5)
check(notch.centerX == -864, "MacBook left of an external display", "\(notch)")
// 13-inch Air with "Larger Text" (1024 pt wide): a narrower notch in points.
notch = NotchLayout.notch(frameMinX: 0, frameWidth: 1024, leftWidth: 437, rightWidth: 437)
check(notch.centerX == 512 && notch.width == 150, "13-inch, larger text", "\(notch)")
// 16-inch with "More Space" (2056 pt wide): a wider notch.
notch = NotchLayout.notch(frameMinX: 0, frameWidth: 2056, leftWidth: 913, rightWidth: 913)
check(notch.centerX == 1028 && notch.width == 230, "16-inch, more space", "\(notch)")
// Missing or nonsense values fall back to a centred default.
notch = NotchLayout.notch(frameMinX: 100, frameWidth: 1440, leftWidth: nil, rightWidth: 700)
check(notch.centerX == 820 && notch.width == NotchLayout.defaultWidth, "fallback when areas are missing", "\(notch)")
notch = NotchLayout.notch(frameMinX: 0, frameWidth: 1440, leftWidth: 10, rightWidth: 10)
check(notch.width == NotchLayout.defaultWidth, "fallback when the measured notch is implausible", "\(notch)")

// MARK: Pause-aligned chunking

/// 16 kHz "speech" (a tone) with silent gaps at the given (start, end) seconds.
func signal(seconds: Double, gaps: [(Double, Double)]) -> [Int16] {
    (0..<Int(seconds * 16000)).map { i in
        let t = Double(i) / 16000
        if gaps.contains(where: { t >= $0.0 && t < $0.1 }) { return 0 }
        return Int16(9000 * sin(2 * Double.pi * 220 * t))
    }
}
func seconds(_ cut: Int?) -> Double? { cut.map { Double($0) / 16000 } }

var audio = signal(seconds: 5, gaps: [(2, 2.5)])
check(PauseChunker.cut(audio[...]) == nil, "no cut before 6 s")
audio = signal(seconds: 10, gaps: [(4, 4.5), (7, 7.4)])
if let s = seconds(PauseChunker.cut(audio[...])) {
    check(abs(s - 7.2) < 0.05, "cuts in the middle of the latest pause", "\(s)")
} else { check(false, "finds the pause at 7–7.4 s") }
audio = signal(seconds: 10, gaps: [(7, 7.15)])
check(PauseChunker.cut(audio[...]) == nil, "a 0.15 s gap isn't a pause")
audio = signal(seconds: 12, gaps: [])
check(PauseChunker.cut(audio[...]) == nil, "keeps listening without a pause before 20 s")
audio = signal(seconds: 21, gaps: [])
check(PauseChunker.cut(audio[...]) != nil, "forces a cut at 20 s with no pause")
// A slice that doesn't start at index 0 (the unsent remainder of a recording).
let longer = signal(seconds: 3, gaps: []) + signal(seconds: 10, gaps: [(7, 7.4)])
if let s = seconds(PauseChunker.cut(longer[(3 * 16000)...])) {
    check(abs(s - 7.2) < 0.05, "offset is relative to the slice", "\(s)")
} else { check(false, "finds the pause in an offset slice") }

// MARK: Joining chunk transcripts

check(ChunkJoiner.join(["We have two open roles.", "And we have five candidates."])
      == "We have two open roles, and we have five candidates.", "continuation word joins with a comma")
check(ChunkJoiner.join(["The role is hard to fill.", "So we're using an agency."])
      == "The role is hard to fill, so we're using an agency.", "so")
check(ChunkJoiner.join(["First, the launch.", "We're aiming for March."])
      == "First, the launch. We're aiming for March.", "a real new sentence stays a sentence")
check(ChunkJoiner.join(["Is that right?", "And then?"]) == "Is that right? And then?", "questions aren't merged")
check(ChunkJoiner.join(["Wait...", "And then"]) == "Wait... And then", "ellipsis isn't merged")
check(ChunkJoiner.join(["Android is next.", "Andrew owns it."]) == "Android is next. Andrew owns it.",
      "only whole words count (Andrew isn't 'and')")
check(ChunkJoiner.join(["", " One. ", "", "Two."]) == "One. Two.", "empty chunks and spaces are ignored")
check(ChunkJoiner.join(["Single chunk."]) == "Single chunk.", "one chunk is unchanged")
check(ChunkJoiner.join(["See you then.", ChunkJoiner.hardBreak, "So, next topic."]) == "See you then. So, next topic.",
      "never merges across a skipped stretch of silence or noise")
check(ChunkJoiner.join(["With the team.", ChunkJoiner.hardBreak, "so I wanted an update"]) == "With the team. So I wanted an update",
      "capitalises a new sentence after a break")
check(ChunkJoiner.join(["on the quarterly roadmap", "The payments team finished."])
      == "on the quarterly roadmap. The payments team finished.", "restores a full stop Whisper dropped at a seam")
check(ChunkJoiner.join(["and then", "I said no."]) == "and then I said no.", "'I' doesn't start a new sentence")
check(ChunkJoiner.join(["we met", "and talked."]) == "we met and talked.", "lowercase continuations just join")
check(ChunkJoiner.join(["Two roles.", ChunkJoiner.hardBreak, "Hiring.", "And then more."]) == "Two roles. Hiring, and then more.",
      "merging resumes after the chunk following a break")

// MARK: Speech detection (silence and noise must never reach Whisper)

var noiseGen = SystemRandomNumberGenerator()
func noise(seconds: Double, level: Double) -> [Int16] {
    (0..<Int(seconds * 16000)).map { _ in Int16(Double.random(in: -1...1, using: &noiseGen) * level * 32768 * 1.7) }
}
func hum(seconds: Double) -> [Int16] {
    (0..<Int(seconds * 16000)).map { i in Int16(0.01 * 32768 * sin(2 * Double.pi * 120 * Double(i) / 16000)) }
}
let speechLike = signal(seconds: 3, gaps: [(1, 1.2)])
check(!SpeechDetector.containsSpeech([Int16](repeating: 0, count: 8 * 16000)[...]), "silence has no speech")
check(!SpeechDetector.containsSpeech(noise(seconds: 8, level: 0.003)[...]), "room noise has no speech")
check(!SpeechDetector.containsSpeech(hum(seconds: 8)[...]), "fan hum has no speech")
check(SpeechDetector.containsSpeech(speechLike[...]), "speech is detected")
check(SpeechDetector.containsSpeech((noise(seconds: 2, level: 0.003) + speechLike)[...]), "speech over noise is detected")
let speechThenNoise = speechLike + noise(seconds: 6, level: 0.003)
let end = Double(SpeechDetector.endOfSpeech(speechThenNoise[...])) / 16000
check(abs(end - 3.4) < 0.1, "trailing noise is trimmed (speech ends at 3 s + 0.4 s padding)", "\(end)")
check(SpeechDetector.endOfSpeech(noise(seconds: 3, level: 0.003)[...]) == 0, "no speech → nothing to keep")

// MARK: Repetition loops

check(RepetitionFilter.collapse("This is a test. Theair of Ourevra. Theair of Ourevra. Theair of Ourevra. Theair of Ourevra. Done.")
      == "This is a test. Theair of Ourevra. Done.", "a loop collapses to one sentence")
check(RepetitionFilter.collapse("No. No. I said yes.") == "No. No. I said yes.", "two in a row is kept")
check(RepetitionFilter.collapse("One. Two. Three.") == "One. Two. Three.", "normal text is unchanged")
check(RepetitionFilter.lastSentence(of: "First part. Second part, which matters.") == "Second part, which matters.",
      "context is the last sentence")
check(RepetitionFilter.lastSentence(of: String(repeating: "a", count: 300)).count == 120, "context is capped")

print(failures == 0 ? "✓ all \(checks) checks passed" : "\(failures) of \(checks) checks failed")
exit(failures == 0 ? 0 : 1)
