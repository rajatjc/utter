import Foundation

/// Usage totals per day. Only counts are kept (no text), so stats survive
/// history being cleared or turned off.
public struct UsageStats: Codable, Equatable, Sendable {
    public struct Day: Codable, Equatable, Sendable {
        public var words = 0
        public var dictations = 0
        /// Seconds spent speaking.
        public var seconds: Double = 0
        public init() {}
    }

    /// Keyed by local date, "yyyy-MM-dd".
    public var days: [String: Day] = [:]
    /// Typing speed used for "time saved" (words per minute).
    public static let typingWPM: Double = 40

    public init() {}

    static func key(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    public mutating func record(words: Int, seconds: Double, at date: Date, calendar: Calendar = .current) {
        var day = days[Self.key(date, calendar)] ?? Day()
        day.words += words
        day.dictations += 1
        day.seconds += seconds
        days[Self.key(date, calendar)] = day
    }

    /// The last `count` days ending on `date`, oldest first (missing days are zero).
    public func lastDays(_ count: Int, endingAt date: Date, calendar: Calendar = .current) -> [(date: Date, day: Day)] {
        let today = calendar.startOfDay(for: date)
        return (0..<count).reversed().map { offset in
            let d = calendar.date(byAdding: .day, value: -offset, to: today)!
            return (d, days[Self.key(d, calendar)] ?? Day())
        }
    }

    public func total(_ count: Int, endingAt date: Date, calendar: Calendar = .current) -> Day {
        lastDays(count, endingAt: date, calendar: calendar).reduce(into: Day()) { sum, entry in
            sum.words += entry.day.words
            sum.dictations += entry.day.dictations
            sum.seconds += entry.day.seconds
        }
    }

    public var allTime: Day {
        days.values.reduce(into: Day()) { sum, d in
            sum.words += d.words; sum.dictations += d.dictations; sum.seconds += d.seconds
        }
    }

    /// Minutes saved versus typing the same words at `typingWPM`.
    public static func minutesSaved(_ day: Day) -> Double {
        max(0, Double(day.words) / typingWPM - day.seconds / 60)
    }

    /// Consecutive days with at least one dictation, ending today (or yesterday).
    public func streak(endingAt date: Date, calendar: Calendar = .current) -> Int {
        var d = calendar.startOfDay(for: date)
        if days[Self.key(d, calendar)] == nil { d = calendar.date(byAdding: .day, value: -1, to: d)! }
        var count = 0
        while let day = days[Self.key(d, calendar)], day.dictations > 0 {
            count += 1
            d = calendar.date(byAdding: .day, value: -1, to: d)!
        }
        return count
    }
}

/// How long dictation history is kept.
public enum HistoryRetention: String, CaseIterable, Codable, Sendable {
    case forever, days30, days7, off

    public var label: String {
        switch self {
        case .forever: "Forever"
        case .days30: "30 days"
        case .days7: "7 days"
        case .off: "Don't keep history"
        }
    }

    /// Items older than this are removed; nil keeps everything.
    public func cutoff(now: Date) -> Date? {
        switch self {
        case .forever: nil
        case .days30: now.addingTimeInterval(-30 * 86400)
        case .days7: now.addingTimeInterval(-7 * 86400)
        case .off: .distantFuture
        }
    }
}
