import UtterCore
import AppKit
import SwiftUI

// MARK: - Vocabulary

struct VocabularyPage: View {
    @AppStorage(Prefs.dictionaryKey) private var dictionary = ""
    @AppStorage(Prefs.snippetsKey) private var snippets = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(title: "Vocabulary", subtitle: "Teach Utter your names and jargon, and set up phrases that expand.")
            EditorCard(title: "Personal dictionary",
                       hint: "One word or name per line. Helps both the recognizer and Claude spell it right.",
                       placeholder: "Kubernetes\nAda Lovelace\nAcme", text: $dictionary)
            EditorCard(title: "Snippets",
                       hint: "One per line, as trigger => expansion. Say the trigger while dictating.",
                       placeholder: "my calendar link => https://cal.com/you\nmy address => 123 Main St", text: $snippets)
        }
    }
}

private struct EditorCard: View {
    let title: String
    let hint: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.system(size: 13, weight: .semibold))
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(placeholder)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                    }
                    TextEditor(text: $text)
                        .font(.system(size: 12, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                }
                .frame(height: 120)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
                Text(hint).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
}

