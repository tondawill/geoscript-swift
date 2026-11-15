// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GeoEngine",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [.library(name: "GeoEngine", targets: ["GeoEngine"])],
    targets: [
        .target(name: "GeoEngine"),
        .testTarget(name: "GeoEngineTests", dependencies: ["GeoEngine"], exclude: ["steps-parity.json", "graphs-parity.json"], resources: [.copy("parity.json")]),
    ]
)
