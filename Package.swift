// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "openSketch",
    platforms: [.macOS(.v15)],
    products: [.library(name: "OpenSketchCore", targets: ["OpenSketchCore"]), .executable(name: "openSketch", targets: ["openSketchApp"])],
    targets: [
        .target(name: "OpenSketchCore"),
        .target(name: "OpenSketchUI", dependencies: ["OpenSketchCore"]),
        .executableTarget(name: "openSketchApp", dependencies: ["OpenSketchUI"]),
        .testTarget(name: "OpenSketchUITests", dependencies: ["OpenSketchUI"]),
        .testTarget(name: "OpenSketchCoreTests", dependencies: ["OpenSketchCore"])
    ],
    swiftLanguageModes: [.v6]
)
