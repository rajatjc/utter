import UtterCore
import Foundation

/// Usage counts per day in ~/Library/Application Support/Utter/stats.json.
/// Only numbers are stored (words, dictations, seconds), never text.
@MainActor
final class StatsStore: ObservableObject {
    static let shared = StatsStore()

    @Published private(set) var stats = UsageStats()

    private var url: URL { WhisperPaths.supportDirectory.appendingPathComponent("stats.json") }

    init() {
        if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode(UsageStats.self, from: data) {
            stats = saved
        }
    }

    func record(words: Int, seconds: Double) {
        stats.record(words: words, seconds: seconds, at: Date())
        if let data = try? JSONEncoder().encode(stats) { try? data.write(to: url, options: .atomic) }
    }

    func reset() {
        stats = UsageStats()
        try? FileManager.default.removeItem(at: url)
    }

    #if DEBUG
    /// Fills a week of made-up numbers so documentation screenshots never show real usage.
    func useDemoData() {
        var demo = UsageStats()
        let words = [420, 610, 0, 880, 540, 1210, 760]
        for (i, count) in words.enumerated() where count > 0 {
            let day = Calendar.current.date(byAdding: .day, value: i - 6, to: Date())!
            for _ in 0..<max(1, count / 60) {
                demo.record(words: 60, seconds: 24, at: day)
            }
        }
        stats = demo
    }
    #endif

    var thisWeek: UsageStats.Day { stats.total(7, endingAt: Date()) }
}
