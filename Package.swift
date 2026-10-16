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
            swiftSettings: [.swiftLanguageMode(.v6)],
            // SwiftPM 6.4's default build system (swiftbuild) stamps LC_BUILD_VERSION with sdk = the deployment
            // target (15.0) instead of the SDK it built against. SwiftUI picks behaviors by that stamp, and a
            // binary "linked against macOS 15" on macOS 26+ loses taps inside the swipe rows and never shrinks
            // the menu bar window. Say the real SDK; Scripts/release.sh refuses a binary without it.
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-platform_version", "-Xlinker", "macos", "-Xlinker", "15.0", "-Xlinker", "27.0"]),
                // `swift run` has no bundle: give the bare executable an Info.plist (LSUIElement, a debug identifier)
                // so it behaves like the packaged app. Release builds get theirs from Scripts/make-app.sh.
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", "\(Context.packageDirectory)/Scripts/Info-debug.plist"], .when(configuration: .debug)),
            ]
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
