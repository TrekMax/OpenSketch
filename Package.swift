// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenSketch",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [.library(name: "OpenSketchCore", targets: ["OpenSketchCore"]), .executable(name: "OpenSketch", targets: ["OpenSketchApp"])],
    targets: [
        .target(name: "OpenSketchCore"),
        .target(name: "OpenSketchUI", dependencies: ["OpenSketchCore"], resources: [.process("Localization/Resources")]),
        .executableTarget(name: "OpenSketchApp", dependencies: ["OpenSketchUI"]),
        .testTarget(name: "OpenSketchUITests", dependencies: ["OpenSketchUI"]),
        .testTarget(name: "OpenSketchCoreTests", dependencies: ["OpenSketchCore"])
    ],
    swiftLanguageModes: [.v6]
)
