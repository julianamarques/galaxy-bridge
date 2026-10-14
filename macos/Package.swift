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
        .package(url: "https://github.com/apple/swift-certificates", exact: "1.21.0"),
    ],
    targets: [
        .target(
            name: "GalaxyKit",
            dependencies: ["PhoneNumberKit"],
            path: "Sources/GalaxyKit"
        ),
        .target(
            name: "BridgeProtocol",
            dependencies: [.product(name: "X509", package: "swift-certificates")],
            path: "Sources/BridgeProtocol"
        ),
        .executableTarget(
            name: "GalaxyBridge",
            dependencies: ["GalaxyKit", "BridgeProtocol"],
            path: "Sources/GalaxyBridge"
        ),
        .testTarget(
            name: "GalaxyKitTests",
            dependencies: ["GalaxyKit"]
        ),
        .testTarget(
            name: "BridgeProtocolTests",
            dependencies: ["BridgeProtocol"]
        ),
    ]
)
