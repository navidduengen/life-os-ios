// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LifeOSKit",
    defaultLocalization: "de",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "LifeOSKit", targets: ["LifeOSKit"]),
    ],
    targets: [
        .target(name: "LifeOSKit"),
        .testTarget(name: "LifeOSKitTests", dependencies: ["LifeOSKit"]),
    ]
)
