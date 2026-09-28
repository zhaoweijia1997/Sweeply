import AppKit
import SwiftUI

/// Renders the main window in every language to PNG files, to check layouts
/// without clicking through the app, and for README screenshots:
///
///     build.noindex/Sweeply.app/Contents/MacOS/Sweeply --snapshot <folder>
///
/// Uses made-up scan results; nothing on this Mac is scanned.
@MainActor
enum Snapshots {
    static let size = NSSize(width: 780, height: 680)

    static func render(to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for language in AppLanguage.allCases where language != .system {
            let pages: [(String, ScanModel, ContentView.Tab)] = [
                ("main", .sample, .clean), ("cleaned", .sampleAfterCleanup, .clean), ("system", .sample, .system),
                ("disk", .sample, .disk), ("devices", .sample, .devices),
            ]
            for (name, model, tab) in pages {
            for dark in [false, true] {
                let view = ContentView(
                    model: model, system: .sample, disk: DiskHealthModel(state: .loaded(.sample)),
                    devices: PeripheralsModel(peripherals: .sample, live: false), tab: tab)
                    .environment(\.locale, language.locale)
                    .frame(width: size.width, height: size.height)
                    // A borderless off-screen window doesn't paint its background.
                    .background(Color(nsColor: .windowBackgroundColor))
                let file = "\(name)-\(language.rawValue)-\(dark ? "dark" : "light").png"
                if let png = draw(view, dark: dark) {
                    try? png.write(to: folder.appending(path: file))
                }
            }
            }
        }
    }

    /// Draws the view in an off-screen window, so AppKit-backed controls
    /// (buttons, menus, scroll views) render too. Needs no screen-recording permission.
    private static func draw(_ view: some View, dark: Bool) -> Data? {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        // Let SwiftUI finish a layout pass before drawing.
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        return bitmap.representation(using: .png, properties: [:])
    }
}

extension Peripherals {
    /// Made-up devices for screenshots.
    static let sample = Peripherals(
        displays: [Display(id: 1, name: "External Display", pixelWidth: 3840, pixelHeight: 2160, refreshRate: 60, isBuiltIn: false)],
        drives: [
            Drive(path: "/Volumes/Backup", name: "Backup", capacity: 2_000_000_000_000, available: 1_240_000_000_000,
                  format: "APFS", connection: .usb),
            Drive(path: "/Volumes/Photos", name: "Photos", capacity: 1_000_000_000_000, available: 310_000_000_000,
                  format: "APFS", connection: .thunderbolt),
        ],
        usb: [
            USBDevice(id: 1, name: "Wireless Receiver", vendor: "Example", speed: 1),
            USBDevice(id: 2, name: "Portable SSD", vendor: "Example", speed: 4),
        ],
        thunderbolt: [ThunderboltDevice(id: 3, name: "Thunderbolt Dock", vendor: "Example")])
}

extension SystemModel {
    /// Made-up readings for screenshots (no real machine's details).
    static var sample: SystemModel {
        let model = SystemModel(machine: SystemStats.Machine(
            chip: "Apple M-series", performanceCores: 8, efficiencyCores: 4, logicalCores: 12,
            bootDate: Date().addingTimeInterval(-(5 * 86400 + 3 * 3600))), live: false)
        let gib: UInt64 = 1 << 30
        model.showForSnapshot(
            coreUsage: [0.12, 0.18, 0.09, 0.22, 0.64, 0.41, 0.35, 0.92, 0.28, 0.15, 0.51, 0.33],
            memory: SystemStats.Memory(
                total: 32 * gib, app: 11 * gib, wired: 3 * gib, compressed: 2 * gib,
                cachedFiles: 9 * gib, swapUsed: 0, pressure: .normal),
            storage: SystemStats.Storage(total: 494_000_000_000, available: 191_000_000_000))
        return model
    }
}

extension DiskHealth {
    /// Made-up readings for screenshots.
    static let sample = DiskHealth(
        model: "APPLE SSD", capacity: 512_000_000_000, bytesWritten: 10_960_000_000_000, bytesRead: 25_150_000_000_000,
        percentageUsed: 2, availableSpare: 100, spareThreshold: 99, temperature: 32, powerOnHours: 3510,
        powerCycles: 254, unsafeShutdowns: 18, mediaErrors: 0, criticalWarning: 0)
}

extension ScanModel {
    /// Made-up results right after a cleanup, with one item that couldn't move.
    static var sampleAfterCleanup: ScanModel {
        let model = sample
        let summary = CleanupSummary(
            moved: [FoundItem(url: URL(fileURLWithPath: "/Users/you/Library/Logs/old"), size: 8_860_000_000)],
            notMoved: [FoundItem(url: URL(fileURLWithPath: "/Users/you/Library/Caches/com.example.locked"), size: 1)])
        model.showCleanupForSnapshot(summary)
        return model
    }

    /// Made-up results for screenshots.
    static var sample: ScanModel {
        let gb: Int64 = 1_000_000_000
        let mb: Int64 = 1_000_000
        func found(_ folder: String, _ items: [(String, Int64)]) -> CategoryResult {
            CategoryResult(items: items.map { FoundItem(url: URL(fileURLWithPath: "/Users/you/\(folder)/\($0.0)"), size: $0.1) })
        }
        var appCaches = found("Library/Caches", [
            ("com.example.editor", 1_400 * mb), ("com.example.music", 820 * mb), ("com.example.chat", 360 * mb),
        ])
        appCaches.skippedRunning = ["com.example.browser"]
        return ScanModel(results: [
            "xcode.derivedData": found("Library/Developer/Xcode/DerivedData", [("MyApp-abcdefgh", 3 * gb), ("Demo-ijklmnop", 1_200 * mb)]),
            "xcode.caches": found("Library/Caches/com.apple.dt.Xcode", [("DocumentationCache", 420 * mb)]),
            "xcode.deviceSupport": found("Library/Developer/Xcode/iOS DeviceSupport", [("iPhone15,2 17.5 (21F79)", 4 * gb), ("iPhone15,2 18.0 (22A3354)", 3 * gb)]),
            "xcode.archives": found("Library/Developer/Xcode/Archives", [("2026-05-01", 225 * mb)]),
            "simulator.caches": CategoryResult(),
            "gradle": found(".gradle/caches", [("modules-2", 900 * mb), ("transforms-4", 300 * mb)]),
            "homebrew": found("Library/Caches/Homebrew", [("downloads", 190 * mb)]),
            "packageCaches": found("Library/Caches", [("pip", 180 * mb), ("CocoaPods", 64 * mb)]),
            "app.caches": appCaches,
            "app.logs": found("Library/Logs", [("DiagnosticReports", 30 * mb)]),
        ])
    }
}
