import Foundation

/// The startup disk's used space over time, noted together with the writes (whenever Sweeply
/// is open, at most once an hour), to show whether something keeps eating space. macOS keeps
/// no such history, so it starts the first time Sweeply notes it. Stored on this Mac only:
/// dates and byte counts, nothing else.
struct DiskSpaceHistory: Codable, Equatable, Sendable {
    struct Sample: Codable, Equatable, Sendable {
        var date: Date
        var used: Int64
        var total: Int64
    }

    struct Day: Identifiable, Equatable, Sendable {
        var date: Date
        var used: Int64
        var id: Date { date }
    }

    private(set) var samples: [Sample] = []

    /// Keeps one sample per hour (the latest), about a year of them at most.
    mutating func record(used: Int64, total: Int64, at date: Date = Date()) {
        // A different size means a different disk: start over.
        if let last = samples.last, last.total != total {
            samples.removeAll()
        }
        if let last = samples.last, date.timeIntervalSince(last.date) < 3600 {
            samples[samples.count - 1] = Sample(date: last.date, used: used, total: total)
        } else {
            samples.append(Sample(date: date, used: used, total: total))
        }
        if samples.count > 8_760 { samples.removeFirst(samples.count - 8_760) }
    }

    var firstDate: Date? { samples.first?.date }
    var latest: Sample? { samples.last }

    /// Used space at the end of each of the last `count` calendar days that Sweeply was open
    /// on (oldest first). Days without a sample are left out, not guessed.
    func days(_ count: Int, until now: Date = Date(), calendar: Calendar = .current) -> [Day] {
        let first = calendar.date(byAdding: .day, value: -(count - 1), to: calendar.startOfDay(for: now))!
        var perDay: [Date: Int64] = [:]
        // Samples are in time order, so each day keeps its latest.
        for sample in samples where sample.date >= first {
            perDay[calendar.startOfDay(for: sample.date)] = sample.used
        }
        return perDay.keys.sorted().map { Day(date: $0, used: perDay[$0]!) }
    }

    /// How much more is used now than on the first of those days (negative when space was
    /// freed); nil until there are two days to compare.
    func change(_ count: Int, until now: Date = Date(), calendar: Calendar = .current) -> Int64? {
        let days = days(count, until: now, calendar: calendar)
        guard days.count >= 2, let first = days.first, let last = days.last else { return nil }
        return last.used - first.used
    }

    // MARK: Storage

    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Sweeply/disk-space.json")
    }

    static func load(from url: URL = defaultURL) -> DiskSpaceHistory {
        guard let data = try? Data(contentsOf: url),
              let history = try? JSONDecoder().decode(DiskSpaceHistory.self, from: data) else { return DiskSpaceHistory() }
        return history
    }

    func save(to url: URL = defaultURL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}
