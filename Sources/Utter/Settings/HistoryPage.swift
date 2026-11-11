import UtterCore
import AppKit
import SwiftUI

// MARK: - History

struct HistoryPage: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                PageHeader(title: "History", subtitle: "Everything you've dictated or asked. Stored only on this Mac.")
                Spacer()
                if !state.history.isEmpty {
                    Button("Clear") { state.clearHistory() }.buttonStyle(SoftButtonStyle())
                }
            }
            if state.history.isEmpty {
                Card {
                    Text("Nothing here yet. Hold \(Prefs.hotkey(for: .dictation).label) in any text field and start talking.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(state.history) { HistoryRow(item: $0, showTranscript: true) }
                }
            }
        }
    }
}

