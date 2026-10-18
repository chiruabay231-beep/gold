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
        // Strategy engine for the VPS bot server (bot-server/).
        .executable(name: "botkit", targets: ["botkit"]),
    ],
    targets: [
        .target(name: "BacktestKit"),
        .executableTarget(name: "botkit", dependencies: ["BacktestKit"]),
        .testTarget(name: "BacktestKitTests", dependencies: ["BacktestKit"]),
    ]
)
