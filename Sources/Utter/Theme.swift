import UtterCore
import AppKit
import SwiftUI

/// Utter's visual language: a violet → magenta → amber accent, soft cards and
/// rounded type. Note: no @State anywhere. On the macOS 27 SDK it's a macro
/// whose plugin ships only with full Xcode, so view state uses ObservableObject.
enum Theme {
    static let violet = Color(red: 0.49, green: 0.36, blue: 1.00)
    static let magenta = Color(red: 0.93, green: 0.35, blue: 0.70)
    static let amber = Color(red: 1.00, green: 0.62, blue: 0.32)
    static let mint = Color(red: 0.30, green: 0.85, blue: 0.62)
    static let coral = Color(red: 1.00, green: 0.42, blue: 0.38)

    static let brandColors = [violet, magenta, amber]
    static var brand: LinearGradient {
        LinearGradient(colors: brandColors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func colors(for mode: Mode) -> [Color] {
        mode == .dictation ? [magenta, amber] : [violet, magenta]
    }
}

/// The app mark, matching the app icon (scripts/make-icon.swift): a dark
/// rounded tile with a glowing gradient waveform.
struct Orb: View {
    var size: CGFloat = 28
    private let heights: [CGFloat] = [0.28, 0.50, 0.78, 1.0, 0.78, 0.50, 0.28]

    var body: some View {
        let tile = RoundedRectangle(cornerRadius: size * 0.235, style: .continuous)
        ZStack {
            tile.fill(LinearGradient(
                colors: [Color(red: 0.12, green: 0.08, blue: 0.25), Color(red: 0.03, green: 0.02, blue: 0.06)],
                startPoint: .top, endPoint: .bottom
            ))
            RadialGradient(
                colors: [Theme.magenta.opacity(0.5), Theme.violet.opacity(0.2), .clear],
                center: .center, startRadius: 0, endRadius: size * 0.5
            )
            .clipShape(tile)
            HStack(spacing: size * 0.041) {
                ForEach(heights.indices, id: \.self) { i in
                    Capsule().frame(width: size * 0.068, height: size * 0.51 * heights[i])
                }
            }
            .foregroundStyle(LinearGradient(colors: Theme.brandColors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .shadow(color: Theme.magenta.opacity(0.8), radius: size * 0.04)
            tile.strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
        }
        .frame(width: size, height: size)
        .shadow(color: Theme.violet.opacity(0.3), radius: size * 0.15, y: size * 0.06)
    }
}

/// Menu bar glyph: the same seven-bar waveform as a template image, so macOS
/// tints it for light and dark menu bars.
enum MenuBarIcon {
    static let image: NSImage = {
        let heights: [CGFloat] = [0.30, 0.55, 0.80, 1.0, 0.80, 0.55, 0.30]
        let size = NSSize(width: 18, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            let barWidth: CGFloat = 1.8
            let gap: CGFloat = (rect.width - CGFloat(heights.count) * barWidth) / CGFloat(heights.count - 1)
            NSColor.black.setFill()
            for (i, h) in heights.enumerated() {
                let height = max(barWidth, rect.height * h)
                let bar = NSRect(
                    x: CGFloat(i) * (barWidth + gap), y: (rect.height - height) / 2,
                    width: barWidth, height: height
                )
                NSBezierPath(roundedRect: bar, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }()
}

struct KeyCap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.07)))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.15))
            )
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.045)))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08))
            )
    }
}

struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .tracking(1.1)
            .foregroundStyle(.secondary)
    }
}

/// Hover state for views (an ObservableObject because @State needs full Xcode here).
final class HoverFlag: ObservableObject {
    @Published var on = false
}

/// Makes a control feel alive under the pointer: a soft glow in `color`, a
/// slight lift, and a little extra brightness.
struct HoverGlow: ViewModifier {
    var color: Color
    var lift: CGFloat
    @StateObject private var hover = HoverFlag()

    func body(content: Content) -> some View {
        content
            .brightness(hover.on ? 0.06 : 0)
            .shadow(color: color.opacity(hover.on ? 0.6 : 0), radius: hover.on ? 12 : 0)
            .scaleEffect(hover.on ? lift : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hover.on)
            .onHover { hover.on = $0 }
    }
}

extension View {
    func hoverGlow(_ color: Color = Theme.violet, lift: CGFloat = 1.04) -> some View {
        modifier(HoverGlow(color: color, lift: lift))
    }
}

struct BrandButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(LinearGradient(colors: [Theme.violet, Theme.magenta], startPoint: .leading, endPoint: .trailing)))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .hoverGlow(Theme.magenta)
    }
}

struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.primary.opacity(configuration.isPressed ? 0.14 : 0.07)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06)))
            .hoverGlow(Theme.violet)
    }
}

/// Live waveform: bar heights follow the mic level, with a gentle ripple.
struct Waveform: View {
    var level: Float
    var colors: [Color]
    var bars = 18

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = (SnapshotClock.date ?? timeline.date).timeIntervalSinceReferenceDate
            Canvas { context, size in
                let barWidth: CGFloat = 2.6
                let gap = (size.width - CGFloat(bars) * barWidth) / CGFloat(max(bars - 1, 1))
                let level = CGFloat(max(0.08, level))
                let shading = GraphicsContext.Shading.linearGradient(
                    Gradient(colors: colors), startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)
                )
                for i in 0..<bars {
                    let fromCenter = abs(CGFloat(i) - CGFloat(bars - 1) / 2) / (CGFloat(bars) / 2)
                    let envelope = 1 - fromCenter * 0.65
                    let ripple = 0.55 + 0.45 * sin(t * 7 + Double(i) * 0.85)
                    let height = max(3, size.height * level * envelope * CGFloat(ripple))
                    let rect = CGRect(
                        x: CGFloat(i) * (barWidth + gap), y: (size.height - height) / 2,
                        width: barWidth, height: height
                    )
                    context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: shading)
                }
            }
        }
    }
}

struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// Tap-to-copy history entry, shared by the menu and the History page.
final class CopyFlag: ObservableObject {
    @Published var copied = false
}

struct HistoryRow: View {
    let item: HistoryItem
    var showTranscript = false
    @StateObject private var flag = CopyFlag()

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.output, forType: .string)
            flag.copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { flag.copied = false }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle().fill(LinearGradient(colors: Theme.colors(for: item.mode).map { $0.opacity(0.18) }, startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: item.mode == .dictation ? "mic.fill" : "sparkles")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.colors(for: item.mode)[1])
                }
                .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.output)
                        .font(.system(size: 12))
                        .lineLimit(showTranscript ? 4 : 2)
                        .multilineTextAlignment(.leading)
                    if showTranscript, item.mode == .command {
                        Text("You said: \(item.transcript)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Text(flag.copied ? "Copied to clipboard" : meta)
                        .font(.system(size: 10))
                        .foregroundStyle(flag.copied ? AnyShapeStyle(Theme.mint) : AnyShapeStyle(.tertiary))
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.035)))
        }
        .buttonStyle(.plain)
        .hoverGlow(Theme.colors(for: item.mode)[0], lift: 1.01)
        .help("Click to copy")
    }

    private var meta: String {
        let time = item.date.formatted(date: .abbreviated, time: .shortened)
        return [item.app, time].compactMap { $0 }.joined(separator: " · ")
    }
}
