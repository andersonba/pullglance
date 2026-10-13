// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pullglance",
    defaultLocalization: "en",
    platforms: [.macOS("15.4")],   // WKWebExtensionController
    targets: [
        .executableTarget(
            name: "Pullglance",
            path: "Sources/Pullglance",
            resources: [.process("Resources"), .copy("WebExtension/gh-review-assistant")],
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
