import Foundation

/// The drive only keeps a lifetime total of bytes written, so Sweeply notes that total
/// over time (whenever it's open, at most once an hour) to show writes per day.
/// Stored on this Mac only: dates and byte counts, nothing else.
struct DiskWriteHistory: Codable, Equatable, Sendable {
    struct Sample: Codable, Equatable, Sendable {
        var date: Date
        var bytesWritten: Double
    }

    struct Day: Identifiable, Equatable, Sendable {
        var date: Date
        var bytes: Double
        var id: Date { date }
    }

    private(set) var samples: [Sample] = []

    /// Keeps one sample per hour (the latest), about two years of them at most.
    mutating func record(_ bytesWritten: Double, at date: Date = Date()) {
        // A smaller total means a different drive: start over.
        if let last = samples.last, bytesWritten < last.bytesWritten {
            samples.removeAll()
        }
        if let last = samples.last, date.timeIntervalSince(last.date) < 3600 {
            samples[samples.count - 1] = Sample(date: last.date, bytesWritten: bytesWritten)
        } else {
            samples.append(Sample(date: date, bytesWritten: bytesWritten))
        }
        if samples.count > 17_520 { samples.removeFirst(samples.count - 17_520) }
    }

    var firstDate: Date? { samples.first?.date }

    /// Writes per calendar day for the last `count` days (oldest first). When Sweeply
    /// wasn't open for a few days, what was written in between is spread evenly over them.
    func days(_ count: Int, until now: Date = Date(), calendar: Calendar = .current) -> [Day] {
        let today = calendar.startOfDay(for: now)
        var perDay: [Date: Double] = [:]
        for (previous, next) in zip(samples, samples.dropFirst()) {
            let from = calendar.startOfDay(for: previous.date)
            let to = calendar.startOfDay(for: next.date)
            let written = next.bytesWritten - previous.bytesWritten
            let span = max(calendar.dateComponents([.day], from: from, to: to).day ?? 0, 0)
            if span == 0 {
                perDay[to, default: 0] += written
            } else {
                for offset in 1...span {
                    let day = calendar.date(byAdding: .day, value: offset, to: from)!
                    perDay[day, default: 0] += written / Double(span)
                }
            }
        }
        return (0..<count).reversed().map { back in
            let day = calendar.date(byAdding: .day, value: -back, to: today)!
            return Day(date: day, bytes: perDay[day] ?? 0)
        }
    }

    /// Average per day since the first sample; nil until there's at least a day of history.
    func averagePerDay(until now: Date = Date()) -> Double? {
        guard let first = samples.first, let last = samples.last else { return nil }
        let days = last.date.timeIntervalSince(first.date) / 86_400
        return days >= 1 ? (last.bytesWritten - first.bytesWritten) / days : nil
    }

    // MARK: Storage

    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Sweeply/disk-writes.json")
    }

    static func load(from url: URL = defaultURL) -> DiskWriteHistory {
        guard let data = try? Data(contentsOf: url),
              let history = try? JSONDecoder().decode(DiskWriteHistory.self, from: data) else { return DiskWriteHistory() }
        return history
    }

    func save(to url: URL = defaultURL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}
