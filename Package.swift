// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GalaxyBridge",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GalaxyKit", targets: ["GalaxyKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/PhoneNumberKit/PhoneNumberKit", exact: "5.0.11"),
    ],
    targets: [
        .target(
            name: "GalaxyKit",
            dependencies: ["PhoneNumberKit"],
            path: "Sources/GalaxyKit"
        ),
        .executableTarget(
            name: "GalaxyBridge",
            dependencies: ["GalaxyKit"],
            path: "Sources/GalaxyBridge"
        ),
        .testTarget(
            name: "GalaxyKitTests",
            dependencies: ["GalaxyKit"]
        ),
    ]
)
