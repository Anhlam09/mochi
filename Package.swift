// swift-tools-version:6.0
import PackageDescription

// Tests live in the `MochiChecks` executable (`swift run MochiChecks`) instead of
// a Swift Testing target: this machine's Command Line Tools ship a mismatched
// Testing.framework that silently discovers zero tests.
let package = Package(
    name: "Mochi",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic: timer engine, presets, settings, system monitoring.
        .target(name: "MochiCore"),
        // Reusable views: mascot shapes, poses, progress ring, floating panel.
        .target(name: "MochiUI", dependencies: ["MochiCore"]),
        // The menu bar app itself.
        .executableTarget(name: "Mochi", dependencies: ["MochiCore", "MochiUI"]),
        // `swift run MochiChecks`: logic checks.
        .executableTarget(name: "MochiChecks", dependencies: ["MochiCore"]),
        // `swift run MochiPreview <outdir>`: renders mascot poses to PNG.
        .executableTarget(name: "MochiPreview", dependencies: ["MochiCore", "MochiUI"]),
    ]
)
