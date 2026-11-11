import UtterCore
import AppKit
import SwiftUI

// MARK: - History

struct HistoryPage: View {
    @EnvironmentObject var state: AppState
    @AppStorage(Prefs.historyRetentionKey) private var retention = HistoryRetention.forever.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                PageHeader(title: "History", subtitle: "Everything you've dictated or asked. Stored only on this Mac.")
                Spacer()
                if !state.history.isEmpty {
                    Button("Clear") { state.clearHistory() }.buttonStyle(SoftButtonStyle())
                }
            }
            Card(padding: 4) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keep history").font(.system(size: 13, weight: .medium))
                        Text("Older dictations are deleted automatically. Stats are kept either way (counts only).")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("", selection: $retention) {
                        ForEach(HistoryRetention.allCases, id: \.self) { Text($0.label).tag($0.rawValue) }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                    .onChange(of: retention) { _, _ in state.applyHistoryRetention() }
                }
                .padding(12)
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

