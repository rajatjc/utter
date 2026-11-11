import UtterCore
import AppKit
import SwiftUI

// MARK: - Floating pill

struct FloatingBarView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Group {
            if state.hudIsIdle {
                DockRow(showOrb: true)
            } else {
                SessionRow()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(red: 0.06, green: 0.05, blue: 0.09).opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: state.hudColors.map { $0.opacity(state.hudIsIdle ? 0.35 : 0.6) },
                                   startPoint: .leading, endPoint: .trailing),
                    lineWidth: 1
                )
        )
        .shadow(color: state.hudColors[0].opacity(state.hudIsIdle ? (state.barHovering ? 0.3 : 0.18) : 0.35), radius: 18, y: 4)
        .shadow(color: .black.opacity(0.4), radius: 10, y: 6)
        .padding(18)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: state.hudPhaseKey)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: state.barHovering)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: state.isMuted)
        .environment(\.colorScheme, .dark)
        .fixedSize()
    }
}

