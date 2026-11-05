// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "openSketch",
    platforms: [.macOS(.v15)],
    products: [.library(name: "OpenSketchCore", targets: ["OpenSketchCore"])],
    targets: [
        .target(name: "OpenSketchCore"),
        .testTarget(name: "OpenSketchCoreTests", dependencies: ["OpenSketchCore"])
    ],
    swiftLanguageModes: [.v6]
)
