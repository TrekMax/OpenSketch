// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "openSketch",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [.library(name: "OpenSketchCore", targets: ["OpenSketchCore"]), .executable(name: "openSketch", targets: ["openSketchApp"])],
    targets: [
        .target(name: "OpenSketchCore"),
        .target(name: "OpenSketchUI", dependencies: ["OpenSketchCore"], resources: [.process("Localization/Resources")]),
        .executableTarget(name: "openSketchApp", dependencies: ["OpenSketchUI"]),
        .testTarget(name: "OpenSketchUITests", dependencies: ["OpenSketchUI"]),
        .testTarget(name: "OpenSketchCoreTests", dependencies: ["OpenSketchCore"])
    ],
    swiftLanguageModes: [.v6]
)
