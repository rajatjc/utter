import UtterCore
import AppKit
import SwiftUI

/// An organic blob outline: a few broad, out-of-step bulges (lopsided, never a
/// regular polygon) that slowly morph, plus a gentle ripple while you speak.
struct BlobShape: Shape {
    /// Phase of the slow morph (accumulated, never jumps).
    var flow: Double
    /// Phase of the speaking ripple (accumulated, never jumps).
    var buzz: Double
    /// Size of the broad bulges, as a fraction of the radius.
    var wobble: Double
    /// Size of the speaking ripple, as a fraction of the radius.
    var vibration: Double

    // (lobes, speed, phase, weight). Lobe 1 shifts the mass to one side, which
    // is what makes it look lopsided and alive rather than geometric.
    private static let bulges: [(Double, Double, Double, Double)] = [
        (1, 0.55, 0.0, 0.30), (2, -0.83, 1.3, 0.45), (3, 0.61, 2.1, 0.28), (4, -0.47, 0.7, 0.12),
    ]

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let maxBend = 1.15 * wobble + vibration
        let radius = min(rect.width, rect.height) / 2 / (1 + maxBend) // stays inside rect
        let n = 160
        var points: [CGPoint] = []
        points.reserveCapacity(n)
        for i in 0..<n {
            let a = Double(i) / Double(n) * 2 * .pi
            var bend = 0.0
            for (lobes, speed, phase, weight) in Self.bulges {
                bend += weight * sin(lobes * a + flow * speed + phase)
            }
            let ripple = 0.6 * sin(5 * a + buzz) + 0.4 * sin(6 * a - 1.2 * buzz + 1.7)
            let r = radius * (1 + wobble * bend + vibration * ripple)
            points.append(CGPoint(x: c.x + CGFloat(cos(a)) * r, y: c.y + CGFloat(sin(a)) * r))
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

/// Frame-to-frame motion state for the blob. Phases are integrated over time
/// (so changing speed never makes the shape jump) and the mic level is eased
/// (so the blob responds smoothly instead of twitching with every sample).
final class BlobMotion: ObservableObject {
    private var last: Date?
    private(set) var level: Double = 0
    private(set) var flow: Double = 0
    private(set) var buzz: Double = 0
    private(set) var drift: Double = 0

    func step(to now: Date, target: Double, calm: Bool) {
        let dt = min(1.0 / 30, max(0, last.map { now.timeIntervalSince($0) } ?? 0))
        last = now
        // Rise quickly-ish, fall slowly, both eased.
        let tau = target > level ? 0.12 : 0.4
        level += (target - level) * (1 - exp(-dt / tau))
        let l = calm ? 0 : level
        flow += dt * (0.9 + 1.4 * l)
        buzz += dt * (3.0 + 6.0 * l)
        drift += dt * (0.25 + 0.5 * l)
    }
}

/// A dark, organic blob lit only at its rim, like light caught in the edge of
/// liquid glass: warm on one side, cool on the other, with a bright streak.
///
/// - At rest it morphs slowly and the colours drift around the rim.
/// - While you speak, the rim brightens and widens and the edge ripples, all
///   eased so it stays smooth.
/// - thinking: calm, slow morph.
/// - done: settles round, a completion ring draws around it, then a check.
/// - failed: settles amber with an exclamation mark.
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

    /// Rim palette: warm → cool, like the reference.
    private var rim: [Color] {
        switch mood {
        case .listening: [Theme.amber, colors[0], Theme.violet, Color(red: 0.42, green: 0.45, blue: 1.0)]
        case .thinking: [Theme.magenta, Theme.violet, Color(red: 0.42, green: 0.45, blue: 1.0)]
        case .done, .failed: colors
        }
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let now = timeline.date
            let age = now.timeIntervalSince(since)
            let settled = mood == .done || mood == .failed
            let _ = motion.step(to: now, target: mood == .listening ? Double(level) : 0,
                                calm: mood != .listening)
            let lv = preview?.level ?? motion.level
            let flow = preview?.flow ?? motion.flow
            let drift = preview?.drift ?? motion.drift
            // Smoothstep from 1 to 0 over half a second when settling.
            let s = settled ? max(0, 1 - age / 0.5) : 1
            let settle = s * s * (3 - 2 * s)
            let wobble = (mood == .thinking ? 0.09 : 0.1 + 0.05 * lv) * settle
            let vibration = (mood == .listening ? 0.022 * lv : 0) * settle
            let blob = size * 0.82
            let shape = BlobShape(flow: flow, buzz: preview != nil ? flow * 4 : motion.buzz,
                                  wobble: wobble, vibration: vibration)
            let angle = Angle.degrees(drift * 57.3 * 0.8)
            // Warm light top-left, cool bottom-right, slowly rotating.
            let rimGradient = AngularGradient(colors: rim + [rim[0]], center: .center, angle: angle)
            let glow = 0.75 + 0.6 * lv

            ZStack {
                // Faint halo outside the rim.
                shape
                    .stroke(rimGradient, lineWidth: 3)
                    .blur(radius: 5)
                    .opacity(0.35 + 0.4 * lv)
                    .frame(width: blob, height: blob)

                ZStack {
                    // Near-black body, so it melts into the notch.
                    shape.fill(RadialGradient(colors: [Color(white: 0.02), Color(white: 0.05)],
                                              center: .center, startRadius: 0, endRadius: blob / 2))

                    // Inner rim glow: wide, soft, fading inward (the main look).
                    shape
                        .stroke(rimGradient, lineWidth: blob * (0.22 + 0.08 * lv))
                        .blur(radius: blob * 0.08)
                        .opacity(glow)
                        .mask(shape)

                    // Tighter, brighter band right at the edge.
                    shape
                        .stroke(rimGradient, lineWidth: blob * 0.07)
                        .blur(radius: blob * 0.025)
                        .opacity(min(1, glow))
                        .mask(shape)

                    // A bright streak of light sliding slowly along the cool side.
                    Ellipse()
                        .fill(RadialGradient(colors: [rim[rim.count - 1].opacity(0.95), .clear],
                                             center: .center, startRadius: 0, endRadius: blob * 0.28))
                        .frame(width: blob * 0.62, height: blob * 0.2)
                        .offset(y: blob * 0.38)
                        .rotationEffect(.degrees(-25 + 28 * sin(drift * 1.3)))
                        .blendMode(.plusLighter)
                        .blur(radius: 2)
                        .opacity(0.55 + 0.4 * lv)
                        .mask(shape)
                }
                .frame(width: blob, height: blob)

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
                            .font(.system(size: blob * 0.3, weight: .heavy))
                            .foregroundStyle(.white)
                            .scaleEffect(min(1, (age - 0.65) / 0.15 + 0.5))
                    }
                }
                if mood == .failed {
                    Image(systemName: "exclamationmark")
                        .font(.system(size: blob * 0.3, weight: .heavy))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Rectangle()) // nothing escapes the frame
        }
        .frame(width: size, height: size)
    }
}
