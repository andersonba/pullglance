import Foundation

extension Bundle {
    /// Resource bundle of this package target. The main bundle of a SwiftPM executable
    /// does not contain our resources, so every localized string must go through this.
    ///
    /// Inside `Pullglance.app` the bundle lives in `Contents/Resources/`, a place the
    /// SwiftPM-generated `.module` accessor never looks (it checks the .app root, then an
    /// absolute `.build/` path that only exists on the build machine). Resolve it ourselves first.
    static let app: Bundle = AppInfo.resourceBundle(inResourcesDirectory: Bundle.main.resourceURL) ?? .module
}

enum AppInfo {
    static let bundleID = "com.andersonba.pullglance"
    static let resourceBundleName = "Pullglance_Pullglance.bundle"

    static func resourceBundle(inResourcesDirectory directory: URL?) -> Bundle? {
        guard let directory else { return nil }
        let url = directory.appendingPathComponent(resourceBundleName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return Bundle(url: url)
    }
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
}

import ServiceManagement
import os

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Only works from a real .app bundle. From `swift run` the call throws and is logged.
    static func set(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            Logger(subsystem: AppInfo.bundleID, category: "login").error("launch at login failed: \(String(describing: error), privacy: .public)")
        }
    }
}
