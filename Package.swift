// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FileMaster",
    platforms: [.macOS("27.0")],
    products: [
        .executable(name: "FileMaster", targets: ["FMApp"]),
        .executable(name: "fm-bench", targets: ["fm-bench"]),
    ],
    targets: [
        // No AppKit. Filesystem, model, sorting, keymap engine. Unit-testable headless.
        .target(name: "FMCore"),
        // Preview loaders (ImageIO, QuickLook thumbnails, text/hex sniffing). No AppKit views.
        .target(name: "FMPreview", dependencies: ["FMCore"]),
        // The AppKit application.
        .executableTarget(name: "FMApp", dependencies: ["FMCore", "FMPreview"]),
        // Listing/sorting micro-benchmarks: `make bench DIR=/some/dir`.
        .executableTarget(name: "fm-bench", dependencies: ["FMCore"]),
        .testTarget(name: "FMCoreTests", dependencies: ["FMCore"]),
        .testTarget(name: "FMPreviewTests", dependencies: ["FMPreview"]),
    ]
)
