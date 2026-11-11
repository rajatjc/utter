import UtterCore
import AppKit
import SwiftUI

/// An organic blob outline: a few broad, out-of-step bulges that slowly morph,
/// a gentle ripple while you speak, and optional random spikes for the jolt
/// when speech starts.
struct BlobShape: Shape {
    typealias Bulge = (lobes: Double, speed: Double, phase: Double, weight: Double)

    /// Random edge spikes, set when the voice jumps from quiet to loud.
    struct Spike {
        var amount = 0.0
        var lobes = 3.0
        var lobes2 = 7.0
        var phase = 0.0
        static let none = Spike()
    }

    /// Phase of the slow morph (accumulated, never jumps).
    var flow: Double
    /// Phase of the speaking ripple (accumulated, never jumps).
    var buzz: Double
    /// Size of the broad bulges, as a fraction of the radius.
    var wobble: Double
    /// Size of the speaking ripple, as a fraction of the radius.
    var vibration: Double
    var bulges: [Bulge] = BlobShape.classic
    /// Turns the whole outline (radians).
    var rotation: Double = 0
    var spike: Spike = .none

    /// Lobe 1 shifts the mass to one side, so it looks lopsided and alive.
    static let classic: [Bulge] = [
        (1, 0.55, 0.0, 0.30), (2, -0.83, 1.3, 0.45), (3, 0.61, 2.1, 0.28), (4, -0.47, 0.7, 0.12),
    ]

    /// The orb's three overlapping copies: an oval, a rounded triangle and a
    /// soft square. Different shapes keep each outline recognisable where they cross.
    static let trio: [[Bulge]] = [
        [(2, 0.40, 0.0, 0.90), (3, -0.50, 1.0, 0.15), (1, 0.30, 2.0, 0.10)],
        [(3, -0.45, 0.5, 0.85), (2, 0.60, 1.4, 0.15), (4, 0.30, 0.2, 0.10)],
        [(2, -0.35, 2.2, 0.55), (4, 0.50, 0.9, 0.45), (1, 0.70, 0.0, 0.10)],
    ]

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let maxBend = 1.15 * wobble + vibration + spike.amount
        let radius = min(rect.width, rect.height) / 2 / (1 + maxBend) // stays inside rect
        let n = 120
        var points: [CGPoint] = []
        points.reserveCapacity(n)
        for i in 0..<n {
            let a = Double(i) / Double(n) * 2 * .pi
            var bend = 0.0
            for (lobes, speed, phase, weight) in bulges {
                bend += weight * sin(lobes * a + flow * speed + phase)
            }
            let ripple = 0.6 * sin(5 * a + buzz) + 0.4 * sin(6 * a - 1.2 * buzz + 1.7)
            let spikes = spike.amount * (0.65 * sin(spike.lobes * a + spike.phase)
                                         + 0.35 * sin(spike.lobes2 * a - 1.7 * spike.phase))
            let r = radius * (1 + wobble * bend + vibration * ripple + spikes)
            let angle = a + rotation
            points.append(CGPoint(x: c.x + CGFloat(cos(angle)) * r, y: c.y + CGFloat(sin(angle)) * r))
        }
        // Smooth closed curve: quadratic segments through the midpoints.
        var p = Path()
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        p.move(to: mid(points[n - 1], points[0]))
        for i in 0..<n {
            p.addQuadCurve(to: mid(points[i], points[(i + 1) % n]), control: points[i])
        }
        p.closeSubpath()
        return p
    }
}

/// Frame-to-frame motion for the three blobs. Phases are integrated over time
/// (so changing speed never makes a shape jump) and the mic level is eased.
///
/// When the voice jumps from quiet to loud, `energy` spikes: each blob gets a
/// random spin kick, its edge spikes at random spots and the orb shakes. The
/// energy fades in about half a second, back to smooth motion.
final class BlobMotion: ObservableObject {
    static let speeds = [1.0, 1.35, 0.75]
    static let directions = [1.0, -1.0, 0.6]

    private var last: Date?
    private var previousTarget = 0.0
    private var cooldown = 0.0
    private var jitterClock = 0.0
    private var kick = [0.0, 0.0, 0.0]
    private var spikeSpeed = [0.0, 0.0, 0.0]

    private(set) var level = 0.0
    /// The jolt at speech onset, 0…1.
    private(set) var energy = 0.0
    /// Random -1…1, changed ~30 times a second: shake and flicker during a jolt.
    private(set) var jitter = 0.0
    private(set) var flow = [0.0, 0.0, 0.0]
    private(set) var rotation = [0.0, 2.094, 4.189]
    private(set) var spikes = [BlobShape.Spike](repeating: .none, count: 3)
    private(set) var buzz = 0.0
    private(set) var time = 0.0

    func step(to now: Date, target rawTarget: Double, calm: Bool) {
        let dt = min(1.0 / 30, max(0, last.map { now.timeIntervalSince($0) } ?? 0))
        last = now
        let target = calm ? 0 : rawTarget
        // Rise fast, fall slowly, both eased.
        let tau = target > level ? 0.07 : 0.4
        level += (target - level) * (1 - exp(-dt / tau))

        let jump = target - previousTarget
        previousTarget = target
        cooldown -= dt
        if jump > 0.18, cooldown <= 0 {
            // Biggest from silence straight into speech.
            let amount = min(1, jump * 1.6 + (level < 0.25 ? 0.35 : 0))
            energy = min(1, energy + amount)
            cooldown = 0.12
            for i in 0..<3 {
                kick[i] += (Bool.random() ? -1 : 1) * Double.random(in: 2...6) * amount
                spikes[i].lobes = Double(Int.random(in: 3...8))
                spikes[i].lobes2 = Double(Int.random(in: 7...12))
                spikes[i].phase = Double.random(in: 0..<(2 * .pi))
                spikeSpeed[i] = Double.random(in: -14...14)
            }
        }
        energy *= exp(-dt / 0.45)
        jitterClock -= dt
        if jitterClock <= 0 {
            jitterClock = 0.035
            jitter = Double.random(in: -1...1)
        }
        for i in 0..<3 {
            kick[i] *= exp(-dt / 0.35)
            flow[i] += dt * (0.8 + 1.5 * level + 6 * energy) * Self.speeds[i]
            rotation[i] += dt * ((0.2 + 0.9 * level) * 0.6 * Self.directions[i] + kick[i])
            spikes[i].phase += dt * spikeSpeed[i]
            spikes[i].amount = 0.1 * energy * Double.random(in: 1...1.5)
        }
        buzz += dt * (3 + 7 * level + 25 * energy)
        time += dt
    }
}

/// Three dark blobs sharing one centre, each a different shape with its edge
/// lit in its own colour, so where they overlap stays easy to see.
///
/// - Listening: they turn and morph out of step; louder speech bulges and
///   brightens them, and the start of speech jolts them (see `BlobMotion`).
/// - Thinking: calm, slow morph.
/// - Done: the three settle into one circle, a completion ring draws around
///   it, then a check. Failed: settles amber with an exclamation mark.
///
/// Everything is drawn inside a fixed `size` square, so it never reaches up
/// under the notch.
struct AIOrb: View {
    enum Mood { case listening, thinking, done, failed }

    let mood: Mood
    let level: Float
    let colors: [Color]
    let since: Date
    var size: CGFloat = 56
    /// Snapshots only: render a fixed moment of the morph.
    var preview: (flow: Double, drift: Double, level: Double)? = nil

    @StateObject private var motion = BlobMotion()

    /// One colour per blob.
    private var hues: [Color] {
        let cool = Color(red: 0.42, green: 0.45, blue: 1.0)
        switch mood {
        case .listening: return [Theme.amber, colors[0], cool]
        case .thinking: return [Theme.magenta, Theme.violet, cool]
        case .done, .failed: return [colors[0], colors[colors.count > 1 ? 1 : 0], colors[0]]
        }
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let now = timeline.date
            let age = now.timeIntervalSince(since)
            let settled = mood == .done || mood == .failed
            let _ = motion.step(to: now, target: Double(level), calm: mood != .listening)
            // Smoothstep from 1 to 0 over half a second when settling.
            let s = settled ? max(0, 1 - age / 0.5) : 1
            let settle = s * s * (3 - 2 * s)

            ZStack {
                Canvas { ctx, canvas in draw(&ctx, in: canvas, settle: settle) }

                // Completion.
                if mood == .done {
                    let ring = min(1, max(0, age - 0.2) / 0.45)
                    Circle()
                        .trim(from: 0, to: ring)
                        .stroke(colors[0], style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: size - 3, height: size - 3)
                        .rotationEffect(.degrees(-90))
                    if ring >= 1 {
                        Image(systemName: "checkmark")
                            .font(.system(size: size * 0.25, weight: .heavy))
                            .foregroundStyle(.white)
                            .scaleEffect(min(1, (age - 0.65) / 0.15 + 0.5))
                    }
                }
                if mood == .failed {
                    Image(systemName: "exclamationmark")
                        .font(.system(size: size * 0.25, weight: .heavy))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Rectangle()) // nothing escapes the frame
        }
        .frame(width: size, height: size)
    }

    private func draw(_ ctx: inout GraphicsContext, in canvas: CGSize, settle: Double) {
        let lv = preview?.level ?? motion.level
        let energy = preview == nil ? motion.energy * settle : 0
        let jitter = motion.jitter
        let k = size / 56
        let r = Double(size) * 0.43 * (1 + 0.05 * energy * jitter)
        let center = CGPoint(x: canvas.width / 2 + CGFloat(energy * jitter * 0.025) * size,
                             y: canvas.height / 2 + CGFloat(energy * sin(motion.time * 53) * 0.02) * size)
        let wobble = (mood == .thinking ? 0.11 : 0.15 + 0.08 * lv + 0.05 * energy) * settle
        let vibration = (0.025 * lv + 0.03 * energy) * settle
        let hues = self.hues

        let paths: [Path] = (0..<3).map { i in
            let ri = CGFloat(r * (1 - 0.03 * Double(i) * settle))
            var spike = preview == nil ? motion.spikes[i] : .none
            spike.amount *= settle
            let flow = preview.map { $0.flow * BlobMotion.speeds[i] + Double(i) * 2.2 } ?? motion.flow[i]
            let rotation = preview.map { Double(i) * 2.094 + $0.drift * 0.6 * BlobMotion.directions[i] }
                ?? motion.rotation[i]
            return BlobShape(flow: flow, buzz: motion.buzz, wobble: wobble, vibration: vibration,
                             bulges: BlobShape.trio[i], rotation: rotation, spike: spike)
                .path(in: CGRect(x: center.x - ri, y: center.y - ri, width: 2 * ri, height: 2 * ri))
        }
        let flicker = 1 + 0.5 * energy * jitter
        let blob = CGFloat(2 * r)

        // Faint halo outside each edge.
        var halo = ctx
        halo.blendMode = .plusLighter
        halo.drawLayer { layer in
            layer.addFilter(.blur(radius: 4 * k))
            for i in 0..<3 {
                layer.stroke(paths[i], with: .color(hues[i].opacity(min(1, (0.15 + 0.25 * lv + 0.3 * energy) * flicker))),
                             lineWidth: 2.5 * k)
            }
        }

        // Near-black bodies, so the orb melts into the notch.
        for path in paths { ctx.fill(path, with: .color(Color(white: 0.043))) }

        // Soft glow just inside each edge.
        for i in 0..<3 {
            var glow = ctx
            glow.blendMode = .plusLighter
            glow.clip(to: paths[i])
            glow.drawLayer { layer in
                layer.addFilter(.blur(radius: blob * 0.035))
                // Kept low: three glows add up, and too much washes the overlaps white.
                layer.stroke(paths[i], with: .color(hues[i].opacity(min(1, 0.28 + 0.2 * lv + 0.2 * energy))),
                             lineWidth: blob * (0.09 + 0.04 * lv))
            }
        }

        // Crisp edges on top: these make each outline traceable through the overlaps.
        var edges = ctx
        edges.blendMode = .plusLighter
        for i in 0..<3 {
            edges.stroke(paths[i], with: .color(hues[i].opacity(min(1, (0.7 + 0.3 * lv) * flicker))),
                         lineWidth: 1.4 * k)
        }
    }
}
