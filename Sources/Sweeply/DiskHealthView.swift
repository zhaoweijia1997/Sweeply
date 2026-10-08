import Charts
import SwiftUI

struct DiskHealthView: View {
    let model: DiskHealthModel

    @Environment(\.locale) private var locale

    var body: some View {
        Group {
            switch model.state {
            case .notLoaded, .loading:
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Reading disk health…").foregroundStyle(.secondary)
                }
            case .unavailable:
                ScrollView {
                    VStack(spacing: 12) {
                        Image(systemName: "internaldrive")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                        Text("Disk health isn't available for this Mac's built-in disk.")
                            .foregroundStyle(.secondary)
                        Button("Refresh") { model.refresh() }
                    }
                    .multilineTextAlignment(.center)
                    .padding(40)
                    // The used space doesn't depend on the drive's health readings.
                    usedSpace.padding([.horizontal, .bottom], 20)
                }
            case let .loaded(health):
                ScrollView {
                    details(health).padding(20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if case .notLoaded = model.state { model.refresh() }
        }
    }

    private func details(_ health: DiskHealth) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "internaldrive.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: health.model).font(.headline)
                    if let capacity = health.capacity {
                        Text(formatBytes(capacity)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VerdictBadge(verdict: health.verdict)
                Button("Refresh") { model.refresh() }
            }

            HStack(alignment: .top, spacing: 14) {
                Card {
                    Text("Total written").foregroundStyle(.secondary)
                    Text(formatBytes(Int64(health.bytesWritten)))
                        .font(.system(size: 34, weight: .semibold))
                        .monospacedDigit()
                    if let writes = health.fullDiskWrites.map({ Int($0.rounded()) }) {
                        Text("Full-disk writes: about \(writes)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                Card {
                    Text("Life used").foregroundStyle(.secondary)
                    Text(verbatim: "\(health.percentageUsed)%")
                        .font(.system(size: 34, weight: .semibold))
                        .monospacedDigit()
                    ProgressView(value: Double(min(health.percentageUsed, 100)), total: 100)
                        .tint(health.percentageUsed >= 80 ? .orange : .green)
                    Text("The drive's own estimate of how worn it is.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // Cards in a row share the height of the tallest one.
            .fixedSize(horizontal: false, vertical: true)

            writesPerDay
            usedSpace

            Grid(horizontalSpacing: 14, verticalSpacing: 14) {
                GridRow {
                    Stat(title: "Total read", value: formatBytes(Int64(health.bytesRead)))
                    Stat(title: "Temperature", value: health.temperature.map(celsius) ?? "—")
                }
                GridRow {
                    Stat(title: "Available spare", value: "\(health.availableSpare)%",
                         note: "Reserve blocks that take over from worn-out ones.")
                    Stat(title: "Power-on time", value: hours(health.powerOnHours))
                }
                GridRow {
                    Stat(title: "Power cycles", value: count(health.powerCycles))
                    Stat(title: "Unsafe shutdowns", value: count(health.unsafeShutdowns),
                         note: "Times the Mac lost power without shutting down properly.")
                }
                GridRow {
                    Stat(title: "Media errors", value: count(health.mediaErrors),
                         note: "Data the drive couldn't read back. Should stay at 0.",
                         warning: health.mediaErrors > 0)
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                }
            }

            Text("Apple doesn't publish how much its SSDs are rated to write. “Life used” is the drive's own estimate and the best guide.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var writesPerDay: some View {
        let history = model.history
        let days = history.days(30)
        let average = history.averagePerDay().map { formatBytes(Int64($0)) }
        let today = formatBytes(Int64(days.last?.bytes ?? 0))
        let since = history.firstDate?.formatted(.dateTime.year().month().day().locale(locale))
        return Card {
            HStack {
                Text("Writes per day").foregroundStyle(.secondary)
                Spacer()
                if let average {
                    Text("Average: \(average) a day").fontWeight(.medium)
                }
            }
            if average == nil {
                Text("Sweeply notes the total whenever it's open. Check back tomorrow to see your first day.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Chart(days) { day in
                    BarMark(x: .value("Day", day.date, unit: .day), y: .value("Written", day.bytes))
                        .foregroundStyle(Color.accentColor.gradient)
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let bytes = value.as(Double.self) { Text(verbatim: formatBytes(Int64(bytes))) }
                        }
                    }
                }
                .frame(height: 130)
                Text("Today: \(today)").font(.callout)
            }
            if let since {
                Text("Recorded since \(since), on this Mac only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Used space at the end of each day for 30 days, and how much it changed: a line that
    /// keeps climbing means something is eating space. The scale starts near the lowest day,
    /// not at zero, so a few gigabytes show.
    private var usedSpace: some View {
        let history = model.space
        let days = history.days(30)
        let change = history.change(30)
        let since = history.firstDate?.formatted(.dateTime.year().month().day().locale(locale))
        let today = Calendar.current.startOfDay(for: Date())
        let start = Calendar.current.date(byAdding: .day, value: -29, to: today)!
        let low = Double(days.map(\.used).min() ?? 0)
        let high = Double(days.map(\.used).max() ?? 0)
        let margin = max((high - low) / 4, 1_000_000_000)
        return Card {
            HStack {
                Text("Used space").foregroundStyle(.secondary)
                Spacer()
                if let change {
                    Text("Change: \(signedBytes(change))").fontWeight(.medium)
                }
            }
            if days.count < 2 {
                Text("Sweeply notes the used space whenever it's open. Check back tomorrow to see how it changes.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Chart(days) { day in
                    AreaMark(x: .value("Day", day.date, unit: .day),
                             yStart: .value("Used", low - margin), yEnd: .value("Used", Double(day.used)))
                        .foregroundStyle(Color.accentColor.opacity(0.18).gradient)
                    LineMark(x: .value("Day", day.date, unit: .day), y: .value("Used", Double(day.used)))
                        .foregroundStyle(Color.accentColor)
                }
                .chartXScale(domain: start...today)
                .chartYScale(domain: (low - margin)...(high + margin))
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let bytes = value.as(Double.self) { Text(verbatim: formatBytes(Int64(bytes))) }
                        }
                    }
                }
                .frame(height: 130)
            }
            if let latest = history.latest {
                Text("Now: \(formatBytes(latest.used)) used, \(formatBytes(latest.total - latest.used)) available")
                    .font(.callout)
            }
            if let since {
                Text("Recorded since \(since), on this Mac only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// "+12.3 GB" or "−4.1 GB".
    private func signedBytes(_ bytes: Int64) -> String {
        (bytes < 0 ? "−" : "+") + formatBytes(abs(bytes))
    }

    // Numbers and units follow the language chosen in Sweeply, not only the system's.
    private func celsius(_ value: Int) -> String {
        Measurement(value: Double(value), unit: UnitTemperature.celsius)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided).locale(locale))
    }

    private func hours(_ value: Double) -> String {
        Measurement(value: value, unit: UnitDuration.hours)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided).locale(locale))
    }

    private func count(_ value: Double) -> String {
        Int(value).formatted(.number.locale(locale))
    }
}

private struct VerdictBadge: View {
    let verdict: DiskHealth.Verdict

    var body: some View {
        let (text, color): (LocalizedStringKey, Color) = switch verdict {
        case .good: ("Good", .green)
        case .attention: ("Needs attention", .orange)
        case .replace: ("Consider replacing", .red)
        }
        Text(text)
            .font(.callout.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.14), in: Capsule())
    }
}

private struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) { content }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08)))
    }
}

private struct Stat: View {
    let title: LocalizedStringKey
    let value: String
    var note: LocalizedStringKey?
    var warning = false

    var body: some View {
        Card {
            HStack {
                Text(title).foregroundStyle(.secondary)
                Spacer()
                Text(verbatim: value)
                    .fontWeight(.medium)
                    .monospacedDigit()
                    .foregroundStyle(warning ? .orange : .primary)
            }
            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
