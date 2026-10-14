// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Pullglance",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Pullglance",
            path: "Sources/Pullglance",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PullglanceTests",
            dependencies: ["Pullglance"],
            path: "Tests/PullglanceTests",
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
