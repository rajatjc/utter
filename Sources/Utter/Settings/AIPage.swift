import UtterCore
import AppKit
import SwiftUI

// MARK: - AI & dictation

/// API key field state, held in an ObservableObject rather than @State.
final class KeyForm: ObservableObject {
    @Published var draft = ""
    @Published var message = ""

    @MainActor
    func save() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let ok = Keychain.setAPIKey(trimmed)
        AppState.shared.hasAPIKey = ok && !trimmed.isEmpty
        message = !ok ? "Couldn't save to Keychain." : (trimmed.isEmpty ? "Key removed." : "Saved to your Keychain.")
        draft = ""
    }
}

struct AIPage: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var sidecar = WhisperSidecar.shared
    @StateObject private var key = KeyForm()

    @AppStorage(Prefs.modelKey) private var model = Prefs.defaultModel
    @AppStorage(Prefs.speechEngineKey) private var speechEngine = (WhisperPaths.python() != nil ? Prefs.SpeechEngine.whisper : .apple).rawValue
    @AppStorage(Prefs.whisperPythonKey) private var whisperPython = ""
    @AppStorage(Prefs.showLiveTextKey) private var showLiveText = false
    @AppStorage(Prefs.dictationEngineKey) private var engine = Prefs.Engine.apple.rawValue
    @AppStorage(Prefs.cleanupKey) private var cleanup = true
    @AppStorage(Prefs.sendWindowTitleKey) private var sendWindowTitle = true
    @AppStorage(Prefs.localeKey) private var locale = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(title: "AI & dictation", subtitle: "Dictation runs free on your Mac. Voice commands use Claude.")

            SectionLabel(text: "Speech recognition")
            HStack(spacing: 10) {
                ModelCard(name: "Apple Speech", tagline: "Built-in · instant live text",
                          selected: speechEngine == Prefs.SpeechEngine.apple.rawValue) {
                    speechEngine = Prefs.SpeechEngine.apple.rawValue
                }
                ModelCard(name: "Whisper large-v3-turbo", tagline: whisperTagline,
                          selected: speechEngine == Prefs.SpeechEngine.whisper.rawValue) {
                    speechEngine = Prefs.SpeechEngine.whisper.rawValue
                }
            }
            if speechEngine == Prefs.SpeechEngine.whisper.rawValue {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(whisperStatusText)
                                .font(.system(size: 12))
                                .foregroundStyle(whisperFailed ? Theme.coral : .secondary)
                            Spacer()
                            if case .installing = sidecar.status {
                                ProgressView().controlSize(.small)
                            } else if !sidecar.isInstalled, WhisperPaths.isSupported {
                                Button("Install Whisper") { sidecar.install() }.buttonStyle(BrandButtonStyle())
                            } else {
                                Button("Restart") { sidecar.restart() }.buttonStyle(SoftButtonStyle())
                            }
                        }
                        HStack(spacing: 8) {
                            Text("Custom Python (optional)").font(.system(size: 12, weight: .medium))
                            TextField("Default: Utter's own environment", text: $whisperPython)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
                        }
                        Text("While you talk the notch shows the waveform and a timer; when you release, Whisper transcribes the recording (about half a second). Keeps ~1.8 GB of memory in use.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Card(padding: 4) {
                    ToggleRow(title: "Show live text while talking",
                              detail: "Runs Apple's recognizer alongside for a preview. It can drop words after a pause, so it's off by default; the typed text always comes from Whisper.",
                              isOn: $showLiveText)
                }
            }

            SectionLabel(text: "Claude").padding(.top, 4)
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Anthropic API key").font(.system(size: 13, weight: .semibold))
                        Spacer()
                        if state.hasAPIKey {
                            Label("Connected", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.mint)
                        }
                    }
                    HStack(spacing: 8) {
                        SecureField(state.hasAPIKey ? "Paste a new key to replace it" : "sk-ant-…", text: $key.draft)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
                        Button("Save") { key.save() }.buttonStyle(BrandButtonStyle())
                    }
                    Text(key.message.isEmpty ? "Get one at console.anthropic.com. It stays in your Keychain." : key.message)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            SectionLabel(text: "Claude model (commands, and dictation when Claude is the engine)").padding(.top, 4)
            HStack(spacing: 10) {
                ForEach(Prefs.models, id: \.id) { option in
                    ModelCard(name: option.name, tagline: option.tagline, selected: model == option.id) {
                        model = option.id
                    }
                }
            }

            SectionLabel(text: "Cleanup (fillers, punctuation, tone)").padding(.top, 4)
            HStack(spacing: 10) {
                ModelCard(name: "On-device", tagline: LocalModel.isAvailable ? "Free · private · works offline" : "Needs Apple Intelligence",
                          selected: engine == Prefs.Engine.apple.rawValue) { engine = Prefs.Engine.apple.rawValue }
                ModelCard(name: "Claude", tagline: "Best quality · uses your API key",
                          selected: engine == Prefs.Engine.claude.rawValue) { engine = Prefs.Engine.claude.rawValue }
            }
            if engine == Prefs.Engine.apple.rawValue, let reason = LocalModel.unavailableReason {
                Text(reason).font(.system(size: 11)).foregroundStyle(Theme.coral)
            }

            Card(padding: 4) {
                VStack(spacing: 0) {
                    ToggleRow(title: "Polish with AI", detail: "Removes filler words, fixes punctuation and matches the app you're in.", isOn: $cleanup)
                    Divider().padding(.leading, 12)
                    ToggleRow(title: "Use the window title for context", detail: "Helps recognize places like Gmail inside a browser.", isOn: $sendWindowTitle)
                    Divider().padding(.leading, 12)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Speech language").font(.system(size: 13, weight: .medium))
                            Text(languageDetail)
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 12)
                        Picker("", selection: $locale) {
                            ForEach(languageChoices, id: \.id) { Text($0.label).tag($0.id) }
                        }
                        .labelsHidden()
                        .frame(width: 200)
                    }
                    .padding(12)
                }
            }
        }
    }
}

private extension AIPage {
    /// The list from Prefs, plus whatever was typed in the old free-text field.
    var languageChoices: [(id: String, label: String)] {
        var choices = Prefs.speechLanguages
        if !choices.contains(where: { $0.id == locale }) {
            let name = Locale.current.localizedString(forIdentifier: locale) ?? locale
            choices.append((locale, name))
        }
        return choices
    }

    var languageDetail: String {
        switch locale {
        case "":
            let name = Locale.current.localizedString(forIdentifier: Locale.current.identifier) ?? Locale.current.identifier
            return "Uses your Mac's language: \(name)."
        case Prefs.autoDetectLanguage:
            return "Whisper works out the language each time. Best if you switch languages; can misjudge very short clips."
        default:
            return "The language you dictate in."
        }
    }

    var whisperFailed: Bool {
        if case .failed = sidecar.status { return true }
        return false
    }

    var whisperTagline: String {
        switch sidecar.status {
        case .ready: "Local · most accurate · ready"
        case .installing: "Local · most accurate · installing…"
        case .starting: "Local · most accurate · loading…"
        case .failed: sidecar.isInstalled ? "Local · most accurate · not running" : "Local · most accurate · not installed"
        case .off: sidecar.isInstalled ? "Local · most accurate" : "Local · most accurate · not installed"
        }
    }

    var whisperStatusText: String {
        switch sidecar.status {
        case .ready: "Whisper is running and ready."
        case .installing(let line): "Installing: \(line)"
        case .starting: "Starting Whisper and loading the model…"
        case .off: sidecar.isInstalled ? "Whisper is off." : "Whisper isn't installed. Needs Python 3.10+ (brew install python) and about 3 GB."
        case .failed(let reason): reason
        }
    }
}

struct ModelCard: View {
    let name: String
    let tagline: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(name).font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? AnyShapeStyle(Theme.violet) : AnyShapeStyle(.tertiary))
                }
                Text(tagline).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? Theme.violet.opacity(0.12) : Color.primary.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Theme.violet.opacity(0.8) : Color.primary.opacity(0.08), lineWidth: selected ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ToggleRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn).toggleStyle(.switch).labelsHidden().tint(Theme.violet)
        }
        .padding(12)
    }
}

