import Foundation
import Testing
@testable import Pullglance

@Test func searchQueryResourceIsBundled() throws {
    let url = try #require(Bundle.app.url(forResource: "search", withExtension: "graphql"))
    let text = try String(contentsOf: url, encoding: .utf8)
    #expect(text.contains("viewer { login organizations(first: 100)"))
    #expect(text.contains("first: 100"))
}

@Test func resourceBundleIsFoundInsideAppResourcesDirectory() throws {
    let fm = FileManager.default
    let resources = fm.temporaryDirectory.appendingPathComponent("pg-\(UUID().uuidString)")
    let bundleDir = resources.appendingPathComponent("Pullglance_Pullglance.bundle")
    try fm.createDirectory(at: bundleDir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: resources) }

    let found = try #require(AppInfo.resourceBundle(inResourcesDirectory: resources))
    #expect(found.bundleURL.resolvingSymlinksInPath().path == bundleDir.resolvingSymlinksInPath().path)
    #expect(AppInfo.resourceBundle(inResourcesDirectory: fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)) == nil)
    #expect(AppInfo.resourceBundle(inResourcesDirectory: nil) == nil)
}
