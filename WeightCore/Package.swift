// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WeightCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "WeightCore", targets: ["WeightCore"]),
    ],
    targets: [
        .target(name: "WeightCore"),
        .testTarget(name: "WeightCoreTests", dependencies: ["WeightCore"]),
    ],
    swiftLanguageModes: [.v6]
)
