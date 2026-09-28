// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Sweeply",
    platforms: [.macOS(.v14)],
    targets: [
        // Localizations live in Resources/Localization and are copied into the
        // app bundle by build.sh, so SwiftUI finds them in Bundle.main.
        .executableTarget(name: "Sweeply", path: "Sources/Sweeply"),
    ]
)
