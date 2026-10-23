// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Echo",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "1.1.1"),
    ],
    targets: [
        .executableTarget(
            name: "Echo",
            dependencies: [.product(name: "WhisperKit", package: "WhisperKit")],
            path: "Sources/Echo",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
