import UtterCore
import AppKit
import SwiftUI

// MARK: - Get started

struct SetupPage: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                Orb(size: 58)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Talk to your Mac").font(.system(size: 26, weight: .bold, design: .rounded))
                    Text("Four quick steps, then dictate into any app or just say what you want done.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 4)

            ProgressTrack(value: Double(state.setupStepsDone) / 4)
                .padding(.bottom, 4)

            StepRow(number: 1, title: "Microphone", detail: "So Utter can hear you while you hold the key.",
                    done: state.permissions.microphone, actionTitle: "Allow") { Permissions.open(.microphone) }
            StepRow(number: 2, title: "Speech recognition access", detail: "macOS permission to turn speech into text on this Mac.",
                    done: state.permissions.speech, actionTitle: "Allow") { Permissions.open(.speech) }
            StepRow(number: 3, title: "Accessibility",
                    detail: "Lets Utter notice the hotkeys and type into other apps.",
                    done: state.permissions.accessibility, actionTitle: "Open Settings") { Permissions.open(.accessibility) }
            StepRow(number: 4, title: "Speech model",
                    detail: "Accurate, private transcription on this Mac's Neural Engine. One-time download of about 500 MB.",
                    done: state.whisperInstalled, actionTitle: "Download") {
                UserDefaults.standard.set(Prefs.SpeechEngine.parakeet.rawValue, forKey: Prefs.speechEngineKey)
                ParakeetEngine.shared.prepare()
                SettingsRouter.shared.page = .claude
            }

            if state.permissions.microphone, state.permissions.accessibility {
                TryItBox()
            }

            if state.setupStepsDone == 4 {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.mint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("You're all set").font(.system(size: 14, weight: .semibold))
                        Text("Click into any text field, hold \(Prefs.hotkey(for: .dictation).label) and talk. Hold \(Prefs.hotkey(for: .command).label) to give a command.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.mint.opacity(0.12)))
            }
        }
    }
}

private struct ProgressTrack: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(Theme.brand)
                    .frame(width: max(8, geo.size.width * value))
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: value)
            }
        }
        .frame(height: 6)
    }
}

private struct StepRow: View {
    let number: Int
    let title: String
    let detail: String
    let done: Bool
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        Card {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(done ? Theme.mint.opacity(0.18) : Color.primary.opacity(0.07))
                    if done {
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.mint)
                    } else {
                        Text("\(number)").font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                }
                .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                if done {
                    Text("Done").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.mint)
                } else {
                    Button(actionTitle, action: action).buttonStyle(BrandButtonStyle())
                }
            }
        }
    }
}


final class TryItText: ObservableObject {
    @Published var text = ""
}

/// A box to dictate into right here, before trying it in other apps.
private struct TryItBox: View {
    @StateObject private var model = TryItText()

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Try it").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if !model.text.isEmpty {
                        Button("Clear") { model.text = "" }.buttonStyle(SoftButtonStyle())
                    }
                }
                ZStack(alignment: .topLeading) {
                    if model.text.isEmpty {
                        Text("Click here, hold \(Prefs.hotkey(for: .dictation).label), say a sentence, then let go. Try “scratch that” or “new paragraph” too.")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                    }
                    TextEditor(text: $model.text)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                }
                .frame(height: 90)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
            }
        }
    }
}
