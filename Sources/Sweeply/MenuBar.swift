import AppKit
import SwiftUI

/// Keeps the number next to the menu bar icon up to date. Does nothing unless background
/// mode is on and the menu bar shows a number.
@MainActor @Observable
final class MenuBarModel {
    private(set) var cpuUsage: Double?
    private(set) var cpuTemperature: Double?

    private var lastTicks: SystemStats.CPUTicks?
    private var timer: Timer?
    private var readingSensors = false

    func start() {
        guard timer == nil else { return }
        update()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
    }

    private func update() {
        guard AppSettings.backgroundMode else {
            lastTicks = nil
            return
        }
        switch AppSettings.menuBarShows {
        case .icon:
            lastTicks = nil
        case .usage:
            guard let ticks = SystemStats.cpuTicks() else { return }
            if let lastTicks {
                let cores = SystemStats.usage(from: lastTicks, to: ticks)
                cpuUsage = cores.isEmpty ? nil : cores.reduce(0, +) / Double(cores.count)
            }
            lastTicks = ticks
        case .temperature:
            // ~70 ms, so off the main thread.
            guard !readingSensors else { return }
            readingSensors = true
            Task {
                let readings = await Task.detached(priority: .utility) { Sensors.read() }.value
                cpuTemperature = readings.cpuHottest
                readingSensors = false
            }
        }
    }
}

struct MenuBarLabel: View {
    let model: MenuBarModel

    @AppStorage(AppSettings.menuBarShowsKey) private var shows: MenuBarShows = .icon

    var body: some View {
        let icon = Text(Image(nsImage: MenuBarIcon.image))
        switch shows {
        case .icon:
            icon
        case .temperature:
            icon + Text(verbatim: " " + (model.cpuTemperature.map { "\(Int($0.rounded()))°" } ?? "–"))
        case .usage:
            icon + Text(verbatim: " " + (model.cpuUsage.map { "\(Int(($0 * 100).rounded()))%" } ?? "–"))
        }
    }
}

/// The little broom, drawn as a template image so it follows the menu bar's color.
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setFillColor(NSColor.black.cgColor)

            context.saveGState()
            context.translateBy(x: 8, y: 9)
            context.rotate(by: 38 * .pi / 180)
            let handle = CGPath(roundedRect: CGRect(x: -0.9, y: -8.3, width: 1.8, height: 7.4),
                                cornerWidth: 0.9, cornerHeight: 0.9, transform: nil)
            context.addPath(handle)
            let head = CGMutablePath()
            head.move(to: CGPoint(x: -2.3, y: -1.4))
            head.addLine(to: CGPoint(x: 2.3, y: -1.4))
            head.addLine(to: CGPoint(x: 4.3, y: 5.4))
            head.addLine(to: CGPoint(x: -4.3, y: 5.4))
            head.closeSubpath()
            context.addPath(head)
            context.fillPath()
            context.restoreGState()

            // A sparkle where it has swept.
            let center = CGPoint(x: 14, y: 14), radius: CGFloat = 3.4, pinch: CGFloat = 0.55
            let sparkle = CGMutablePath()
            sparkle.move(to: CGPoint(x: center.x, y: center.y - radius))
            sparkle.addQuadCurve(to: CGPoint(x: center.x + radius, y: center.y), control: CGPoint(x: center.x + pinch, y: center.y - pinch))
            sparkle.addQuadCurve(to: CGPoint(x: center.x, y: center.y + radius), control: CGPoint(x: center.x + pinch, y: center.y + pinch))
            sparkle.addQuadCurve(to: CGPoint(x: center.x - radius, y: center.y), control: CGPoint(x: center.x - pinch, y: center.y + pinch))
            sparkle.addQuadCurve(to: CGPoint(x: center.x, y: center.y - radius), control: CGPoint(x: center.x - pinch, y: center.y - pinch))
            context.addPath(sparkle)
            context.fillPath()
            return true
        }
        image.isTemplate = true
        return image
    }()
}

/// The panel that opens from the menu bar icon.
struct MenuBarPanel: View {
    let system: SystemModel
    let disk: DiskHealthModel

    @Environment(\.openWindow) private var openWindow
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                AppIconImage(size: 26)
                Text(verbatim: "Sweeply").font(.headline)
                Spacer()
            }
            Divider()
            VStack(spacing: 7) {
                row("CPU", Text(verbatim: system.cpuUsage.map { percent($0) } ?? "…"))
                if let memory = system.memory {
                    row("Memory", Text(verbatim: "\(memoryBytes(memory.used)) / \(memoryBytes(memory.total))"),
                        color: memory.pressure == .normal ? .primary : .orange)
                }
                if let temperature = system.sensors?.cpuHottest {
                    row("CPU temperature", Text(verbatim: celsius(temperature)), color: temperature >= 90 ? .orange : .primary)
                }
                if let fans = system.sensors?.fans, let fastest = fans.map(\.rpm).max() {
                    row("Fans", Text("\(Int(fastest)) rpm"))
                }
                if let storage = system.storage {
                    row("Startup disk", Text("\(formatBytes(storage.available)) free"))
                }
                if let today = writtenToday {
                    row("Written today", Text(verbatim: formatBytes(today)))
                }
            }
            .font(.callout)
            Divider()
            VStack(spacing: 8) {
                Button {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Text("Open Sweeply").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                HStack {
                    SettingsLink { Text("Settings…") }
                    Spacer()
                    Button("Quit Sweeply") { NSApp.terminate(nil) }
                }
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 320)
        .onAppear { system.start() }
        .onDisappear { system.stop() }
    }

    /// Only once there's a sample from earlier today to compare against.
    private var writtenToday: Int64? {
        guard disk.history.samples.count >= 2, let today = disk.history.days(1).first else { return nil }
        return Int64(today.bytes)
    }

    private func row(_ title: LocalizedStringKey, _ value: Text, color: Color = .primary) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            value.fontWeight(.medium).monospacedDigit().foregroundStyle(color)
        }
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }

    private func memoryBytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
    }

    private func celsius(_ value: Double) -> String {
        Measurement(value: value.rounded(), unit: UnitTemperature.celsius)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))).locale(locale))
    }
}
