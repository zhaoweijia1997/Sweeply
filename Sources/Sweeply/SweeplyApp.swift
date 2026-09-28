import AppKit
import SwiftUI

@main
struct SweeplyApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system
    @State private var model = ScanModel()
    @State private var disk = DiskHealthModel()

    var body: some Scene {
        Window("Sweeply", id: "main") {
            ContentView(model: model, disk: disk)
                .environment(\.locale, language.locale)
                .frame(minWidth: 680, minHeight: 540)
        }
        .defaultSize(width: 780, height: 680)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Sweeply.app/Contents/MacOS/Sweeply --disk-health: print what Disk Health reads, for bug reports.
        // Reads twice through the same path as the tab, like opening it and pressing Refresh.
        if CommandLine.arguments.contains("--disk-health") {
            MainActor.assumeIsolated {
                let model = DiskHealthModel()
                for attempt in 1...2 {
                    model.refresh()
                    if case let .loaded(health) = model.state {
                        print("Read \(attempt): \(health)")
                    } else {
                        print("Read \(attempt): Disk health unavailable")
                    }
                }
            }
            exit(0)
        }
        // Sweeply.app/Contents/MacOS/Sweeply --snapshot <folder>
        if let flag = CommandLine.arguments.firstIndex(of: "--snapshot") {
            let folder = CommandLine.arguments.dropFirst(flag + 1).first ?? "."
            MainActor.assumeIsolated { Snapshots.render(to: URL(fileURLWithPath: folder)) }
            exit(0)
        }
        // Behave like a normal windowed app when started with `swift run`, too.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
