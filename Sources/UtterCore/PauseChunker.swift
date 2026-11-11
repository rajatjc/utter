import Foundation

/// Decides where to cut a recording into chunks that Whisper can transcribe
/// while the user is still talking.
///
/// Cuts land only in the middle of a real pause (a stretch of near-silence),
/// never mid-word: cutting at arbitrary points made Whisper garble or invent
/// words at the seams (7.1% vs 3.8% wrong on a 70 s test), while pause-aligned
/// chunks produced the same text as transcribing everything at once.
public enum PauseChunker {
    public struct Config: Sendable {
        public var sampleRate = 16000
        /// Don't cut before a chunk is this long (fewer seams = better accuracy).
        public var minLength: Double = 6
        /// If no pause shows up by this length, cut at the quietest moment anyway.
        public var maxLength: Double = 20
        /// How long the silence must last to count as a pause.
        public var pause: Double = 0.3
        /// Analysis frame length.
        public var frame: Double = 0.02

        public init() {}
    }

    /// Where to cut `samples` (16-bit mono PCM, the audio not yet sent), as an
    /// offset from the start of `samples`, or nil to keep listening.
    public static func cut(_ samples: ArraySlice<Int16>, config: Config = Config()) -> Int? {
        let sr = Double(config.sampleRate)
        let n = samples.count
        guard Double(n) >= config.minLength * sr else { return nil }

        let hop = max(1, Int(config.frame * sr))
        let frameCount = n / hop
        guard frameCount > 0 else { return nil }
        var rms = [Float](repeating: 0, count: frameCount)
        let base = samples.startIndex
        for f in 0..<frameCount {
            var sum: Float = 0
            let start = base + f * hop
            for i in start..<(start + hop) {
                let v = Float(samples[i]) / 32768
                sum += v * v
            }
            rms[f] = (sum / Float(hop)).squareRoot()
        }

        // "Quiet" is relative to how loud this speaker is (90th percentile), with a floor.
        let loud = rms.sorted()[min(frameCount - 1, Int(Double(frameCount) * 0.9))]
        let threshold = max(loud * 0.08, 0.004)
        let needed = max(1, Int(config.pause / config.frame))
        // Allow pauses from a second before minLength, so a pause there isn't missed.
        let firstAllowed = max(0, Int((config.minLength - 1) * sr) / hop)

        var run = 0
        var best: Int?
        for f in 0..<frameCount {
            run = rms[f] < threshold ? run + 1 : 0
            if run >= needed, f >= firstAllowed {
                best = (f - run / 2) * hop // the middle of the latest qualifying pause
            }
        }
        if let best { return best }

        if Double(n) >= config.maxLength * sr, firstAllowed < frameCount {
            var quietest = firstAllowed
            for f in firstAllowed..<frameCount where rms[f] < rms[quietest] { quietest = f }
            return quietest * hop
        }
        return nil
    }
}
