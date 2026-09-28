import SwiftUI

/// CPU, memory, storage and machine info. Deliberately shows no serial numbers or other
/// identifiers, so screenshots of it are safe to share.
struct SystemView: View {
    let model: SystemModel

    @Environment(\.locale) private var locale

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                machineHeader
                HStack(alignment: .top, spacing: 14) {
                    cpuCard
                    memoryCard
                }
                .fixedSize(horizontal: false, vertical: true)
                storageCard
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    private var machineHeader: some View {
        let machine = model.machine
        return HStack(spacing: 12) {
            Image(systemName: "cpu")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: machine.chip).font(.headline)
                if machine.performanceCores > 0 {
                    Text("Cores: \(machine.performanceCores) performance + \(machine.efficiencyCores) efficiency")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Cores: \(machine.logicalCores)").foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Up for \(uptime(since: machine.bootDate))")
                if let total = model.memory?.total {
                    Text("Memory: \(bytes(total))").foregroundStyle(.secondary)
                }
            }
        }
    }

    private var cpuCard: some View {
        SystemCard(title: "CPU") {
            Text(model.cpuUsage.map(percent) ?? "…")
                .font(.system(size: 34, weight: .semibold))
                .monospacedDigit()
            // One bar per core.
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(model.coreUsage.enumerated()), id: \.offset) { _, usage in
                    GeometryReader { geometry in
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(usage > 0.85 ? Color.orange : Color.accentColor)
                                .frame(height: max(2, geometry.size.height * usage))
                        }
                    }
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 2))
                }
            }
            .frame(height: 44)
            Text("Each bar is one core.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var memoryCard: some View {
        SystemCard(title: "Memory") {
            if let memory = model.memory {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(bytes(memory.used))
                        .font(.system(size: 34, weight: .semibold))
                        .monospacedDigit()
                    Text("of \(bytes(memory.total))")
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: Double(memory.used), total: Double(max(memory.total, 1)))
                    .tint(pressureColor(memory.pressure))
                HStack {
                    Text("Memory pressure")
                    Spacer()
                    Text(pressureText(memory.pressure))
                        .fontWeight(.medium)
                        .foregroundStyle(pressureColor(memory.pressure))
                }
                .font(.callout)
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                    row("App memory", memory.app)
                    row("Wired", memory.wired)
                    row("Compressed", memory.compressed)
                    row("Cached files", memory.cachedFiles)
                    row("Swap used", memory.swapUsed)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Text(verbatim: "…")
            }
        }
    }

    private var storageCard: some View {
        SystemCard(title: "Startup disk") {
            if let storage = model.storage {
                let used = storage.total - storage.available
                HStack(alignment: .firstTextBaseline) {
                    Text("Available: \(formatBytes(storage.available))")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Text("Used \(formatBytes(used)) of \(formatBytes(storage.total))")
                        .foregroundStyle(.secondary)
                }
                .monospacedDigit()
                ProgressView(value: Double(used), total: Double(max(storage.total, 1)))
                    .tint(Double(storage.available) / Double(max(storage.total, 1)) < 0.1 ? .orange : .accentColor)
                Text("Available space includes files macOS can remove on its own when it needs room.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ title: LocalizedStringKey, _ value: UInt64) -> some View {
        GridRow {
            Text(title)
            Text(bytes(value)).monospacedDigit().gridColumnAlignment(.trailing)
        }
    }

    private func pressureText(_ pressure: SystemStats.Memory.Pressure) -> LocalizedStringKey {
        switch pressure {
        case .normal: "Normal"
        case .warning: "Elevated"
        case .critical: "Critical"
        }
    }

    private func pressureColor(_ pressure: SystemStats.Memory.Pressure) -> Color {
        switch pressure {
        case .normal: .green
        case .warning: .orange
        case .critical: .red
        }
    }

    // Memory is counted in binary units, like Activity Monitor.
    private func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }

    private func uptime(since date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        return Duration.seconds(seconds - seconds % 60)
            .formatted(.units(allowed: [.days, .hours, .minutes], width: .abbreviated, maximumUnitCount: 2).locale(locale))
    }
}

private struct SystemCard<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).foregroundStyle(.secondary)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08)))
    }
}
