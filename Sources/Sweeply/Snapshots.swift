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
            for dark in [false, true] {
                let view = ContentView(model: .sample)
                    .environment(\.locale, language.locale)
                    .frame(width: size.width, height: size.height)
                    // A borderless off-screen window doesn't paint its background.
                    .background(Color(nsColor: .windowBackgroundColor))
                let name = "main-\(language.rawValue)-\(dark ? "dark" : "light").png"
                if let png = draw(view, dark: dark) {
                    try? png.write(to: folder.appending(path: name))
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

extension ScanModel {
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
