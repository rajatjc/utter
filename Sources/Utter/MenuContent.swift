import UtterCore
import AppKit
import SwiftUI

struct MenuContent: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if state.setupStepsDone < 4 {
                setupCard
            }

            HStack(spacing: 10) {
                ModeCard(mode: .dictation, title: "Dictate", subtitle: "Hold, talk, release",
                         key: Prefs.hotkey(for: .dictation).label)
                ModeCard(mode: .command, title: "Command", subtitle: "Hold and ask",
                         key: Prefs.hotkey(for: .command).label)
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text("Double-tap").foregroundStyle(.secondary)
                    KeyCap(label: Prefs.hotkey(for: .dictation).label)
                    Text("for hands-free").foregroundStyle(.secondary)
                }
                if state.barStyle == .notch {
                    Label("Move the pointer just under the camera to open the notch controls.", systemImage: "cursorarrow.motionlines")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 11))

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    SectionLabel(text: "Recent")
                    Spacer()
                    if !state.history.isEmpty {
                        Button("See all") { SettingsWindow.show(page: .history) }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.violet)
                            .hoverGlow(Theme.violet, lift: 1.08)
                    }
                }
                if state.history.isEmpty {
                    Text("Nothing yet. Click into any text field, hold \(Prefs.hotkey(for: .dictation).label) and talk.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                } else {
                    ForEach(state.history.prefix(3)) { HistoryRow(item: $0) }
                }
            }

            Divider().opacity(0.6)

            HStack {
                Button { SettingsWindow.show() } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .buttonStyle(SoftButtonStyle())
                Button { state.toggleMute() } label: {
                    Label(state.isMuted ? "Unmute" : "Mute", systemImage: state.isMuted ? "mic.slash.fill" : "mic.slash")
                }
                .buttonStyle(SoftButtonStyle())
                .foregroundStyle(state.isMuted ? Theme.coral : .primary)
                Spacer()
                Button("Quit Utter") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .hoverGlow(Theme.coral, lift: 1.06)
            }
        }
        .padding(16)
        .frame(width: 360)
        .onAppear { state.refreshPermissions() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Orb(size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("Utter").font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("Your voice, everywhere on your Mac")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer()
            StatusPill(phase: state.phase, needsSetup: !state.permissions.accessibility, muted: state.isMuted)
        }
    }

    private var setupCard: some View {
        Button { SettingsWindow.show(page: .setup) } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.1), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: CGFloat(state.setupStepsDone) / 4)
                        .stroke(Theme.brand, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(state.setupStepsDone)/4").font(.system(size: 9, weight: .bold, design: .rounded))
                }
                .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Finish setting up").font(.system(size: 13, weight: .semibold))
                    Text("A few permissions and the speech model")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.violet.opacity(0.14), Theme.magenta.opacity(0.08)], startPoint: .leading, endPoint: .trailing))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ModeCard: View {
    let mode: Mode
    let title: String
    let subtitle: String
    let key: String

    var body: some View {
        // Clicking a card opens the shortcut settings, where its key can be changed.
        Button { SettingsWindow.show(page: .shortcuts) } label: { card }
            .buttonStyle(.plain)
            .hoverGlow(Theme.colors(for: mode)[0], lift: 1.03)
            .help("Change the \(title.lowercased()) shortcut")
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LinearGradient(colors: Theme.colors(for: mode), startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: mode == .dictation ? "mic.fill" : "sparkles")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            KeyCap(label: key)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct StatusPill: View {
    let phase: Phase
    var needsSetup = false
    var muted = false

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(.system(size: 10.5, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.14)))
        .foregroundStyle(color)
    }

    private var text: String {
        switch phase {
        case .listening: "Listening"
        case .processing: "Working"
        case .confirm: "Waiting for you"
        case .failed: "Error"
        default: muted ? "Muted" : needsSetup ? "Setup needed" : "Ready"
        }
    }

    private var color: Color {
        switch phase {
        case .listening: Theme.magenta
        case .processing: Theme.violet
        case .confirm: Theme.amber
        case .failed: Theme.coral
        default: muted ? Theme.coral : needsSetup ? Theme.amber : Theme.mint
        }
    }
}
