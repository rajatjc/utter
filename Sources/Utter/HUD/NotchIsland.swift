import UtterCore
import AppKit
import SwiftUI

// MARK: - Notch island

/// The notch's silhouette: flared ("eared") top corners that blend into the
/// screen edge, straight sides, rounded bottom corners.
struct NotchShape: Shape {
    var ear: CGFloat
    var bottomRadius: CGFloat

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let k: CGFloat = 0.5523 // cubic approximation of a quarter circle
        let e = ear
        let r = min(bottomRadius, (rect.width - 2 * e) / 2, rect.height - e)
        let x0 = rect.minX, x1 = rect.maxX, y0 = rect.minY, y1 = rect.maxY
        var p = Path()
        p.move(to: CGPoint(x: x0, y: y0))
        // Top-left ear: concave fillet from the screen edge into the left side.
        p.addCurve(to: CGPoint(x: x0 + e, y: y0 + e),
                   control1: CGPoint(x: x0 + k * e, y: y0),
                   control2: CGPoint(x: x0 + e, y: y0 + e - k * e))
        p.addLine(to: CGPoint(x: x0 + e, y: y1 - r))
        p.addCurve(to: CGPoint(x: x0 + e + r, y: y1),
                   control1: CGPoint(x: x0 + e, y: y1 - r + k * r),
                   control2: CGPoint(x: x0 + e + r - k * r, y: y1))
        p.addLine(to: CGPoint(x: x1 - e - r, y: y1))
        p.addCurve(to: CGPoint(x: x1 - e, y: y1 - r),
                   control1: CGPoint(x: x1 - e - r + k * r, y: y1),
                   control2: CGPoint(x: x1 - e, y: y1 - r + k * r))
        p.addLine(to: CGPoint(x: x1 - e, y: y0 + e))
        // Top-right ear.
        p.addCurve(to: CGPoint(x: x1, y: y0),
                   control1: CGPoint(x: x1 - e, y: y0 + e - k * e),
                   control2: CGPoint(x: x1 - k * e, y: y0))
        p.closeSubpath()
        return p
    }
}

/// A dynamic island. Idle, it is exactly the notch (so it's invisible and covers
/// nothing). On hover or during a session the notch grows downward and the UI
/// appears inside it, below the camera.
struct NotchIslandView: View {
    @EnvironmentObject var state: AppState
    var geometry: NotchGeometry = .current()

    /// Width of the flared top corners when the island is wider than the notch.
    private let ear: CGFloat = 10

    private var expanded: Bool { !state.hudIsIdle || state.barHovering }

    var body: some View {
        VStack(spacing: 0) {
            // The physical notch: no pixels here, this just reserves its footprint.
            Color.clear.frame(width: geometry.width, height: geometry.bandHeight)
            if expanded {
                Group {
                    if state.hudIsIdle {
                        DockRow(showOrb: false)
                    } else {
                        SessionRow()
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 6) // keeps everything clear of the notch above
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, expanded ? ear : 0)
        .background(NotchShape(ear: expanded ? ear : 0, bottomRadius: expanded ? 22 : 10).fill(Color.black))
        .shadow(color: state.hudColors[0].opacity(expanded ? 0.35 : 0), radius: 14, y: 6)
        .shadow(color: .black.opacity(expanded ? 0.4 : 0), radius: 10, y: 5)
        // Room for the glow only while expanded, so the idle window is just the notch.
        .padding(.horizontal, expanded ? 24 : 0)
        .padding(.bottom, expanded ? 28 : 2)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: state.hudPhaseKey)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: state.barHovering)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: state.isMuted)
        .environment(\.colorScheme, .dark)
        .fixedSize()
    }
}

