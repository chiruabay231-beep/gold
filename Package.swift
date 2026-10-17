// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BacktestKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "BacktestKit", targets: ["BacktestKit"]),
    ],
    targets: [
        .target(name: "BacktestKit"),
        .testTarget(name: "BacktestKitTests", dependencies: ["BacktestKit"]),
    ]
)
