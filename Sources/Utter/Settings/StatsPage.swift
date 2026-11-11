import UtterCore
import AppKit
import SwiftUI

// MARK: - Stats

/// Headline numbers for the week, then words per day as a single-series bar
/// chart (hover a bar for its numbers). Only counts are stored, never text.
struct StatsPage: View {
    @ObservedObject private var store = StatsStore.shared

    var body: some View {
        let week = store.thisWeek
        let allTime = store.stats.allTime
        let days = store.stats.lastDays(7, endingAt: Date())
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(title: "Stats", subtitle: "How much you've said instead of typed. Counts only; no text is kept.")

            HStack(spacing: 10) {
                StatTile(value: week.words.formatted(), label: "words this week")
                StatTile(value: Self.duration(UsageStats.minutesSaved(week)), label: "saved vs typing at 40 wpm")
                StatTile(value: week.dictations.formatted(), label: "dictations this week")
                StatTile(value: "\(store.stats.streak(endingAt: Date()))", label: "day streak")
            }
            .fixedSize(horizontal: false, vertical: true) // equal-height tiles

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Words per day, last 7 days").font(.system(size: 13, weight: .semibold))
                    WordsChart(days: days)
                        .frame(height: 150)
                }
            }

            HStack {
                Text("All time: \(allTime.words.formatted()) words in \(allTime.dictations.formatted()) dictations, about \(Self.duration(UsageStats.minutesSaved(allTime))) saved.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset") { store.reset() }.buttonStyle(SoftButtonStyle())
            }
        }
    }

    static func duration(_ minutes: Double) -> String {
        if minutes < 1 { return "0 min" }
        if minutes < 60 { return "\(Int(minutes.rounded())) min" }
        let hours = minutes / 60
        return hours < 10 ? String(format: "%.1f h", hours) : "\(Int(hours.rounded())) h"
    }
}

private struct StatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}

/// One series, one hue: bars anchored to the baseline with 4 pt rounded tops,
/// a recessive baseline, weekday labels, and a tooltip on hover.
private struct WordsChart: View {
    let days: [(date: Date, day: UsageStats.Day)]

    var body: some View {
        let peak = max(1, days.map(\.day.words).max() ?? 1)
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(days.indices, id: \.self) { i in
                    DayBar(date: days[i].date, day: days[i].day, fraction: CGFloat(days[i].day.words) / CGFloat(peak),
                           isToday: i == days.count - 1)
                }
            }
            Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 1)
            HStack(spacing: 10) {
                ForEach(days.indices, id: \.self) { i in
                    Text(days[i].date.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

private struct DayBar: View {
    let date: Date
    let day: UsageStats.Day
    let fraction: CGFloat
    let isToday: Bool
    @StateObject private var hover = HoverFlag()

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 0,
                                       bottomTrailingRadius: 0, topTrailingRadius: 4, style: .continuous)
                    .fill(Theme.violet.opacity(hover.on ? 1 : (isToday ? 0.95 : 0.75)))
                    .frame(height: day.words == 0 ? 2 : max(4, (geo.size.height - 22) * fraction))
            }
            .frame(maxWidth: .infinity)
            .overlay(alignment: .top) {
                if hover.on {
                    VStack(spacing: 1) {
                        Text(date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                            .font(.system(size: 10, weight: .semibold))
                        Text("\(day.words) words · \(StatsPage.duration(UsageStats.minutesSaved(day))) saved")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.regularMaterial))
                    .fixedSize()
                    .transition(.opacity)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle()) // the whole column is the hover target, not just the bar
        .onHover { hover.on = $0 }
        .animation(.easeOut(duration: 0.12), value: hover.on)
        .accessibilityElement()
        .accessibilityLabel("\(date.formatted(.dateTime.weekday(.wide))): \(day.words) words")
    }
}
