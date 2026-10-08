import AppKit
import SwiftUI

/// Keeps the number next to the menu bar icon up to date. Does nothing unless background
/// mode is on and the menu bar shows a number.
@MainActor @Observable
final class MenuBarModel {
    private(set) var cpuUsage: Double?
    private(set) var cpuTemperature: Double?
    /// What Clean Up would move to the Trash with its default choices.
    private(set) var junkBytes: Int64?

    private var lastTicks: SystemStats.CPUTicks?
    private var timer: Timer?
    private var readingSensors = false
    private var measuringJunk = false
    private var junkMeasured: Date?

    func start() {
        guard timer == nil else { return }
        NotificationCenter.default.addObserver(forName: ScanModel.didClean, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.junkMeasured = nil
                self?.update()
            }
        }
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
        case .junk:
            lastTicks = nil
            // Reading folder sizes takes a few seconds of disk work: every 30 minutes, gently.
            guard !measuringJunk, junkMeasured.map({ Date().timeIntervalSince($0) >= 1800 }) ?? true else { return }
            measuringJunk = true
            let runningApps = ScanModel.runningApps()
            Task {
                junkBytes = await Task.detached(priority: .utility) { Self.measureJunk(runningApps: runningApps) }.value
                junkMeasured = Date()
                measuringJunk = false
            }
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

extension MenuBarModel {
    /// The categories Clean Up ticks by default, without the audio drivers it leaves unticked.
    nonisolated static func measureJunk(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                                        runningApps: Set<String>) -> Int64 {
        CleanCategory.all.filter(\.selectedByDefault).reduce(0) { total, category in
            total + Scanner.scan(category, home: home, runningApps: runningApps).items
                .filter { $0.leftover?.kind != .audioDriver }
                .reduce(0) { $0 + $1.size }
        }
    }
}

struct MenuBarLabel: View {
    let model: MenuBarModel

    @AppStorage(AppSettings.menuBarShowsKey) private var shows: MenuBarShows = .icon

    var body: some View {
        switch shows {
        case .icon:
            Image(nsImage: MenuBarIcon.image)
        case .temperature:
            Image(nsImage: MenuBarIcon.image(followedBy: model.cpuTemperature.map { "\(Int($0.rounded()))°" } ?? "–"))
        case .usage:
            Image(nsImage: MenuBarIcon.image(followedBy: model.cpuUsage.map { "\(Int(($0 * 100).rounded()))%" } ?? "–"))
        case .junk:
            Text(verbatim: model.junkBytes.map(formatBytes) ?? "…")
        }
    }
}

/// The little broom, a template image so it follows the menu bar's color. Drawn into bitmaps
/// up front: an image that draws itself on demand (a drawing handler) shows up blank in the menu
/// bar on recent macOS, which shows status items outside the app's own drawing. A custom image
/// also has to go in as an Image; wrapped in a Text to sit next to a number it is dropped and
/// only the number arrives, so the number is drawn into the same bitmap instead.
enum MenuBarIcon {
    static let image: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        for scale in [1, 2, 3] {
            guard let context = CGContext(data: nil, width: 18 * scale, height: 18 * scale, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
            // Points, with y going down as in the drawing below.
            context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
            context.translateBy(x: 0, y: 18)
            context.scaleBy(x: 1, y: -1)
            draw(in: context)
            guard let cgImage = context.makeImage() else { continue }
            let rep = NSBitmapImageRep(cgImage: cgImage)
            rep.size = size
            image.addRepresentation(rep)
        }
        image.isTemplate = true
        return image
    }()

    /// The broom with a short reading next to it, drawn into one bitmap (see above).
    static func image(followedBy text: String) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributed.size()
        let gap: CGFloat = 3
        let size = NSSize(width: (18 + gap + textSize.width).rounded(.up), height: 18)
        let image = NSImage(size: size)
        for scale in [1, 2, 3] {
            guard let context = CGContext(data: nil, width: Int(size.width) * scale, height: 18 * scale,
                                          bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
            context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
            let graphics = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphics
            attributed.draw(at: NSPoint(x: 18 + gap, y: (18 - textSize.height) / 2))
            NSGraphicsContext.restoreGraphicsState()
            // Points, with y going down as in the drawing below.
            context.translateBy(x: 0, y: 18)
            context.scaleBy(x: 1, y: -1)
            draw(in: context)
            guard let cgImage = context.makeImage() else { continue }
            let rep = NSBitmapImageRep(cgImage: cgImage)
            rep.size = size
            image.addRepresentation(rep)
        }
        image.isTemplate = true
        return image
    }

    private static func draw(in context: CGContext) {
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
    }
}

/// The panel that opens from the menu bar icon.
struct MenuBarPanel: View {
    let system: SystemModel
    let disk: DiskHealthModel
    let brightness: BrightnessModel
    let volume: VolumeModel

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
            let controllable = brightness.displays.filter(\.supported)
            let sound = volume.output.flatMap { $0.canSetVolume ? $0 : nil }
            let monitorSpeakers = brightness.displays.filter { $0.volume != nil }
            if !controllable.isEmpty || sound != nil || !monitorSpeakers.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    if !controllable.isEmpty {
                        Text("Brightness").font(.callout).foregroundStyle(.secondary)
                        ForEach(controllable) { display in
                            if controllable.count > 1 {
                                Text(verbatim: display.name).font(.caption)
                            }
                            BrightnessSlider(model: brightness, display: display)
                        }
                    }
                    if sound != nil || !monitorSpeakers.isEmpty {
                        Text("Volume").font(.callout).foregroundStyle(.secondary)
                            .padding(.top, controllable.isEmpty ? 0 : 4)
                    }
                    // The Mac's sound output, then each monitor's own speakers (over DDC).
                    if let sound {
                        Text(verbatim: sound.name).font(.caption).lineLimit(1)
                        VolumeSlider(model: volume, output: sound)
                    }
                    ForEach(monitorSpeakers) { display in
                        Text(verbatim: display.name).font(.caption).lineLimit(1)
                        MonitorVolumeSlider(model: brightness, display: display)
                    }
                }
            }
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
        .onAppear {
            system.start()
            brightness.refresh()
            volume.start()
        }
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
