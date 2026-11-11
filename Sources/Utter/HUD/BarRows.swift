import UtterCore
import AppKit
import SwiftUI

// MARK: - Shared rows

/// Idle controls: Dictate, Command, mute and settings.
struct DockRow: View {
    @EnvironmentObject var state: AppState
    var showOrb: Bool

    var body: some View {
        HStack(spacing: 8) {
            if showOrb {
                Orb(size: 26).opacity(state.isMuted ? 0.5 : 1)
            }
            BarButton(symbol: "mic.fill", label: "Dictate", colors: Theme.colors(for: .dictation),
                      expanded: state.barHovering) { state.toggle(.dictation) }
                .opacity(state.isMuted ? 0.45 : 1)
            BarButton(symbol: "sparkles", label: "Command", colors: Theme.colors(for: .command),
                      expanded: state.barHovering) { state.toggle(.command) }
                .opacity(state.isMuted ? 0.45 : 1)
            if state.barHovering || state.isMuted {
                BarIconButton(
                    symbol: state.isMuted ? "mic.slash.fill" : "mic.slash",
                    colors: state.isMuted ? [Theme.coral, Theme.amber] : [Color.white.opacity(0.12), Color.white.opacity(0.12)]
                ) { state.toggleMute() }
                .help(state.isMuted ? "Unmute" : "Mute: ignore the hotkeys until unmuted")
                .transition(.opacity.combined(with: .scale(scale: 0.6)))
            }
            if state.barHovering {
                BarIconButton(symbol: "gearshape.fill") { SettingsWindow.show() }
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
            }
        }
    }
}

/// Live session: badge, title, transcript, waveform and hands-free controls.
struct SessionRow: View {
    @EnvironmentObject var state: AppState

    /// Voice-only dictation keeps one fixed footprint from the first word to
    /// "done": the orb on the left and a 150 pt slot that shows the waveform,
    /// then the status, then the result, so the island never changes size.
    private var compact: Bool {
        guard state.sessionMode == .dictation, !state.livePreview else { return false }
        switch state.phase {
        case .listening, .processing, .done, .failed, .notice: return true
        case .idle, .confirm: return false
        }
    }

    @ViewBuilder private var compactSlot: some View {
        ZStack {
            switch state.phase {
            case .listening:
                Waveform(level: state.level, colors: state.hudColors, bars: 28)
                    .frame(width: 150, height: 28)
            case .processing:
                HStack(spacing: 7) {
                    Text(stepTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                    LoadingDots(colors: state.hudColors)
                }
            case .done(let message), .failed(let message), .notice(let message):
                Text(message)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            default:
                EmptyView()
            }
        }
        .frame(width: 150, height: 40)
        .transition(.opacity)
        .padding(.trailing, 4)
        .animation(.easeInOut(duration: 0.2), value: state.hudPhaseKey)
        .animation(.easeInOut(duration: 0.2), value: state.step)
    }

    /// "Polishing…" → "Polishing" (the dots are animated instead).
    private var stepTitle: String {
        let raw = state.step.isEmpty ? "Polishing" : state.step
        return raw.hasSuffix("…") ? String(raw.dropLast()) : raw
    }

    var body: some View {
        HStack(spacing: 10) {
            badge
            if compact {
                compactSlot
            } else if state.hudVoiceOnly {
                // Voice-only: no words, just the orb and the voice.
                Waveform(level: state.level, colors: state.hudColors, bars: 28)
                    .frame(width: 150, height: 28)
                    .padding(.trailing, 4)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text(state.hudTitle)
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .tracking(1.2)
                        .lineLimit(1)
                        .foregroundStyle(.white.opacity(0.45))
                    Text(state.hudDetail)
                        .font(state.hudIsConfirming
                              ? .system(size: 12.5, weight: .medium, design: .monospaced)
                              : .system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(state.hudIsPlaceholder ? 0.45 : 0.95))
                        .lineLimit(state.hudIsConfirming ? 3 : 2)
                        .truncationMode(state.hudIsConfirming ? .tail : .head)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // A fixed width (not maxWidth) so the text's wrapped height is known
                // up front; otherwise a second line overflows the bar.
                .frame(width: 320, alignment: .leading)
            }
            if state.hudIsListening, !state.hudVoiceOnly {
                Waveform(level: state.level, colors: state.hudColors)
                    .frame(width: 76, height: 28)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
            if state.hudIsListening {
                if state.handsFree {
                    BarIconButton(symbol: "checkmark", colors: state.hudColors) {
                        if case .listening(let mode) = state.phase { state.toggle(mode) }
                    }
                    BarIconButton(symbol: "xmark") { state.cancel() }
                }
            }
            if state.hudIsConfirming {
                BarIconButton(symbol: "play.fill", colors: [Theme.mint, Color(red: 0.25, green: 0.75, blue: 0.85)]) {
                    state.resolveConfirmation(true)
                }
                .help("Run")
                BarIconButton(symbol: "xmark") { state.cancel() }
                    .help("Cancel")
            }
        }
        .padding(.trailing, 6)
    }

    @ViewBuilder private var badge: some View {
        switch state.phase {
        case .listening:
            AIOrb(mood: .listening, level: state.level, colors: state.hudColors, since: state.phaseSince)
        case .processing:
            AIOrb(mood: .thinking, level: 0, colors: state.hudColors, since: state.phaseSince)
        case .done:
            AIOrb(mood: .done, level: 0, colors: state.hudColors, since: state.phaseSince)
        case .failed:
            AIOrb(mood: .failed, level: 0, colors: state.hudColors, since: state.phaseSince)
        default:
            iconBadge.frame(width: 32, height: 32).padding(12)
        }
    }

    @ViewBuilder private var iconBadge: some View {
        ZStack {
            switch state.phase {
            default:
                Circle()
                    .fill(LinearGradient(colors: state.hudColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: state.hudColors[1].opacity(0.6), radius: state.hudIsListening ? 4 + CGFloat(state.level) * 10 : 4)
                Image(systemName: state.hudSymbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .scaleEffect(state.hudIsListening ? 1 + CGFloat(state.level) * 0.12 : 1)
        .animation(.easeOut(duration: 0.1), value: state.level)
    }
}


/// Three dots that rise and fade in a wave: the "working on it" indicator.
private struct LoadingDots: View {
    let colors: [Color]

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3.5) {
                ForEach(0..<3, id: \.self) { i in
                    let wave = (sin(t * 6 - Double(i) * 0.9) + 1) / 2
                    Circle()
                        .fill(colors[i % colors.count])
                        .frame(width: 5, height: 5)
                        .opacity(0.35 + 0.65 * wave)
                        .offset(y: -2.5 * wave)
                }
            }
        }
        .frame(width: 24, height: 10)
    }
}

/// Gradient icon that grows a text label when the bar is hovered.
private struct BarButton: View {
    let symbol: String
    let label: String
    let colors: [Color]
    let expanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                ZStack {
                    Circle().fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 26, height: 26)
                if expanded {
                    Text(label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.trailing, 10)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .padding(2)
            .background(Capsule().fill(Color.white.opacity(expanded ? 0.08 : 0)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .hoverGlow(colors.last ?? Theme.violet, lift: 1.06)
        .help(label)
    }
}

private struct BarIconButton: View {
    let symbol: String
    var colors: [Color] = [Color.white.opacity(0.12), Color.white.opacity(0.12)]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 26, height: 26)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .hoverGlow(colors.count > 1 && colors[0] != colors[1] ? colors[1] : Theme.violet, lift: 1.12)
    }
}
