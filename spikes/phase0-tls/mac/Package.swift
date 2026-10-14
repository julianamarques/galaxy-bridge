// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TLSSpikeServer",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-certificates", exact: "1.21.0"),
    ],
    targets: [
        .executableTarget(
            name: "TLSSpikeServer",
            dependencies: [.product(name: "X509", package: "swift-certificates")]
        ),
    ]
)
