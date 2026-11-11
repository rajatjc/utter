import Foundation

/// Finds actual speech in 16 kHz 16-bit audio, so silence and background noise
/// are never sent to Whisper. Whisper invents text for audio without speech
/// ("Thank you." for silence or room noise), and with a context prompt it can
/// echo that prompt back, which is how one bad chunk turned into a loop.
///
/// A 20 ms frame counts as speech when it's clearly louder than the recording's
/// own background level and above an absolute floor. Steady noise (fans, hum,
/// room tone) stays near the background level, so it never qualifies.
public enum SpeechDetector {
    static let frame = 320 // 20 ms at 16 kHz

    static func frameLevels(_ samples: ArraySlice<Int16>) -> [Float] {
        let count = samples.count / frame
        var levels = [Float](repeating: 0, count: count)
        let base = samples.startIndex
        for f in 0..<count {
            var sum: Float = 0
            let start = base + f * frame
            for i in start..<(start + frame) {
                let v = Float(samples[i]) / 32768
                sum += v * v
            }
            levels[f] = (sum / Float(frame)).squareRoot()
        }
        return levels
    }

    /// Per-frame speech flags.
    static func speechFrames(_ samples: ArraySlice<Int16>) -> [Bool] {
        let levels = frameLevels(samples)
        guard !levels.isEmpty else { return [] }
        let background = levels.sorted()[levels.count / 5] // 20th percentile
        // Cap the background estimate so continuous speech with no pauses
        // isn't mistaken for "background".
        let threshold = max(0.006, 4 * min(background, 0.005))
        return levels.map { $0 > threshold }
    }

    /// Seconds of speech in `samples`.
    public static func speechSeconds(_ samples: ArraySlice<Int16>) -> Double {
        Double(speechFrames(samples).filter { $0 }.count * frame) / 16000
    }

    /// Whether `samples` contains enough speech to be worth transcribing.
    public static func containsSpeech(_ samples: ArraySlice<Int16>, minimum: Double = 0.25) -> Bool {
        speechSeconds(samples) >= minimum
    }

    /// Offset just after the last speech in `samples`, plus `padding` seconds,
    /// so trailing silence or noise can be dropped. 0 if there's no speech.
    public static func endOfSpeech(_ samples: ArraySlice<Int16>, padding: Double = 0.4) -> Int {
        let flags = speechFrames(samples)
        guard let last = flags.lastIndex(of: true) else { return 0 }
        return min(samples.count, (last + 1) * frame + Int(padding * 16000))
    }
}

/// Breaks Whisper's repetition loops: a sentence repeated three or more times
/// in a row is kept once. (Two in a row is left alone; people do say that.)
public enum RepetitionFilter {
    public static func collapse(_ text: String) -> String {
        let sentences = split(text)
        guard sentences.count >= 3 else { return text }
        var out: [String] = []
        var i = 0
        while i < sentences.count {
            var j = i + 1
            while j < sentences.count, key(sentences[j]) == key(sentences[i]) { j += 1 }
            let run = j - i
            out.append(contentsOf: run >= 3 ? [sentences[i]] : Array(sentences[i..<j]))
            i = j
        }
        return out.joined(separator: " ")
    }

    static func split(_ text: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        for ch in text {
            current.append(ch)
            if ".!?".contains(ch) {
                let s = current.trimmingCharacters(in: .whitespaces)
                if !s.isEmpty { sentences.append(s) }
                current = ""
            }
        }
        let rest = current.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty { sentences.append(rest) }
        return sentences
    }

    static func key(_ sentence: String) -> String {
        sentence.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// The last sentence of `text`, at most `limit` characters: safe context
    /// for the next chunk (a long or repetitive prompt invites echoes).
    public static func lastSentence(of text: String, limit: Int = 120) -> String {
        let last = split(text).last ?? text
        return String(last.suffix(limit))
    }
}
