import UtterCore
import AppKit
import SwiftUI

// MARK: - Shortcuts

struct ShortcutsPage: View {
    @EnvironmentObject var state: AppState
    @AppStorage(Prefs.showFloatingBarKey) private var showBarWhenIdle = true
    @AppStorage(Prefs.dictationHotkeyKey) private var dictationHotkey = Prefs.HotkeyChord.leftControlOption.rawValue
    @AppStorage(Prefs.commandHotkeyKey) private var commandHotkey = Prefs.HotkeyChord.rightCommand.rawValue

    private let examples: [(String, String)] = [
        ("app.badge", "“Open Slack” · “Quit Spotify”"),
        ("globe", "“Go to github.com” · “Search for flights to Lisbon”"),
        ("text.cursor", "With text selected: “Make this friendlier” · “Translate to French”"),
        ("square.and.pencil", "“Reply saying I'll be ten minutes late”"),
        ("bell", "“Remind me tomorrow at 9 to call Sam”"),
        ("music.note", "“Next song” · “Volume to 30” · “Dark mode”"),
        ("square.stack.3d.up", "“Run my Morning Routine shortcut”"),
        ("questionmark.bubble", "“What's 18% of 240?”"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(title: "Shortcuts", subtitle: "Hold a key chord to talk, or click the floating bar.")
            Card(padding: 4) {
                VStack(spacing: 0) {
                    hotkeyRow(title: "Dictate", detail: "Hold to talk, release to insert. Double-tap for hands-free.",
                              selection: $dictationHotkey)
                    Divider().padding(.leading, 12)
                    hotkeyRow(title: "Command", detail: "Hold, say what to do, release.",
                              selection: $commandHotkey)
                    Divider().padding(.leading, 12)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Cancel").font(.system(size: 13, weight: .medium))
                            Text("Pressing any other key while holding also cancels, so your usual shortcuts keep working.")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        KeyCap(label: "esc")
                    }
                    .padding(12)
                }
            }
            SectionLabel(text: "Bar").padding(.top, 4)
            Card(padding: 4) {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Image(systemName: state.barStyle == .notch ? "rectangle.topthird.inset.filled" : "capsule")
                            .foregroundStyle(Theme.violet)
                            .frame(width: 20)
                        Text(state.barStyle == .notch
                             ? "This Mac has a notch, so Utter lives in it: rest the pointer just under the camera to open the controls."
                             : "This display has no notch, so Utter shows a floating pill you can drag anywhere.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    .padding(12)
                    Divider().padding(.leading, 12)
                    ToggleRow(title: "Show while idle",
                              detail: "Keep the bar on screen so you can hover and click it. Off: it appears only while you talk.",
                              isOn: $showBarWhenIdle)
                    if state.barStyle == .floating {
                        Divider().padding(.leading, 12)
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Pill position").font(.system(size: 13, weight: .medium))
                                Text("Drag it anywhere; this puts it back under the camera.").font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Reset") { state.resetBarPosition() }.buttonStyle(SoftButtonStyle())
                        }
                        .padding(12)
                    }
                }
            }
            SectionLabel(text: "Things to say in command mode").padding(.top, 4)
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(examples, id: \.1) { icon, text in
                        HStack(spacing: 10) {
                            Image(systemName: icon)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.violet)
                                .frame(width: 20)
                            Text(text).font(.system(size: 12))
                        }
                    }
                }
            }
        }
    }

    private func hotkeyRow(title: String, detail: String, selection: Binding<String>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: selection) {
                ForEach(Prefs.HotkeyChord.allCases) { Text($0.label).tag($0.rawValue) }
            }
            .labelsHidden()
            .frame(width: 180)
        }
        .padding(12)
    }
}
