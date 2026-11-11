import UtterCore
import AVFoundation
import Foundation

/// Soft start and stop chimes, synthesised once at launch: two short sine notes
/// with a gentle fade, rising for "listening" and falling for "done".
@MainActor
enum Sounds {
    private static var players: [String: AVAudioPlayer] = [:]

    /// The start chime overlaps the first moment of the recording; this much
    /// leading audio is replaced with silence so the chime is never transcribed.
    static let startChimeLength: Double = 0.18

    static func playStart() { play("start", notes: [(784, 0.07), (1047, 0.11)]) }   // G5 → C6
    static func playStop() { play("stop", notes: [(1047, 0.06), (784, 0.10)]) }     // C6 → G5

    private static func play(_ name: String, notes: [(freq: Double, length: Double)]) {
        guard Prefs.soundsEnabled else { return }
        if players[name] == nil, let data = chime(notes), let player = try? AVAudioPlayer(data: data) {
            player.volume = 0.18
            player.prepareToPlay()
            players[name] = player
        }
        players[name]?.currentTime = 0
        players[name]?.play()
    }

    /// A WAV of the given notes, each with a short attack and an exponential fade.
    private static func chime(_ notes: [(freq: Double, length: Double)]) -> Data? {
        let rate = 44100.0
        var samples: [Int16] = []
        for note in notes {
            let n = Int(note.length * rate)
            for i in 0..<n {
                let t = Double(i) / rate
                let attack = min(1, t / 0.008)
                let decay = exp(-t / (note.length * 0.45))
                let v = sin(2 * .pi * note.freq * t) * 0.6 + sin(4 * .pi * note.freq * t) * 0.1
                samples.append(Int16(max(-1, min(1, v * attack * decay)) * 20000))
            }
        }
        var wav = Data()
        func put<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { wav.append(contentsOf: $0) } }
        let body = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        wav.append(contentsOf: Array("RIFF".utf8)); put(UInt32(36 + body.count))
        wav.append(contentsOf: Array("WAVEfmt ".utf8)); put(UInt32(16))
        put(UInt16(1)); put(UInt16(1)); put(UInt32(44100)); put(UInt32(88200)); put(UInt16(2)); put(UInt16(16))
        wav.append(contentsOf: Array("data".utf8)); put(UInt32(body.count))
        wav.append(body)
        return wav
    }
}
