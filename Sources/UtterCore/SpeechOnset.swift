import Foundation

/// Spots the start of speech in the mic level (0…1): a rise to speaking volume
/// after at least `quietGap` seconds of quiet. The gaps between words are
/// shorter than that, so syllables mid-sentence don't count; a new sentence
/// after a pause does. The orb jolts on each onset.
public struct SpeechOnset: Sendable {
    /// Below this the mic is treated as quiet.
    public var quietLevel = 0.12
    /// At or above this the mic is treated as speech.
    public var speechLevel = 0.25
    /// Seconds of quiet needed before a rise counts as a new start.
    public var quietGap = 0.4

    private var quietFor: Double

    /// `startQuiet`: the first words of a session count as an onset.
    public init(startQuiet: Bool = true) {
        quietFor = startQuiet ? .infinity : 0
    }

    /// Feeds one level sample `dt` seconds after the last. True when this sample starts speech.
    public mutating func update(level: Double, dt: Double) -> Bool {
        let onset = level >= speechLevel && quietFor >= quietGap
        quietFor = level < quietLevel ? quietFor + dt : 0
        return onset
    }
}
