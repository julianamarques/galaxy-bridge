// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SamsungForMac",
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
            name: "SamsungForMac",
            dependencies: ["GalaxyKit"],
            path: "Sources/SamsungForMac"
        ),
        .testTarget(
            name: "GalaxyKitTests",
            dependencies: ["GalaxyKit"]
        ),
    ]
)
