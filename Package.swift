// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Pullglance",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    dependencies: [
        // In-app updates. A binary xcframework; Scripts/make-app.sh embeds it in the bundle and re-signs it.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
        // Opens and closes the MenuBarExtra window from code (the global hotkey); SwiftUI has no API for it.
        .package(url: "https://github.com/orchetect/MenuBarExtraAccess", from: "1.3.1"),
        // The user-chosen global shortcut: a recorder for Settings and the hot key behind it (Carbon, no permissions).
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "3.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "Pullglance",
            dependencies: [.product(name: "Sparkle", package: "Sparkle"), .product(name: "MenuBarExtraAccess", package: "MenuBarExtraAccess"), .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")],
            path: "Sources/Pullglance",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)],
            // SwiftPM 6.4's default build system (swiftbuild) stamps LC_BUILD_VERSION with sdk = the deployment
            // target (15.0) instead of the SDK it built against: it runs swiftc without SDKROOT, swift-driver hands
            // clang `--sysroot`, and clang only reads the SDK version from `-isysroot` or $SDKROOT. SwiftUI picks
            // behaviors by that stamp, and a binary "linked against macOS 15" on macOS 26+ loses taps inside the
            // swipe rows and never shrinks the menu bar window. Say the real SDK; Scripts/release.sh refuses a
            // binary without it. https://github.com/swiftlang/swift-package-manager/issues/10696
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-platform_version", "-Xlinker", "macos", "-Xlinker", "15.0", "-Xlinker", "27.0"]),
                // `swift run` has no bundle: give the bare executable an Info.plist (LSUIElement, a debug identifier)
                // so it behaves like the packaged app. Release builds get theirs from Scripts/make-app.sh.
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", "\(Context.packageDirectory)/Scripts/Info-debug.plist"], .when(configuration: .debug)),
                // Where Sparkle.framework is found at run time: inside the packaged app, and, for the bare
                // `swift run` executable and the test bundle, which have no bundle to carry it, in the SwiftPM artifact.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "\(Context.packageDirectory)/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64"], .when(configuration: .debug)),
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
