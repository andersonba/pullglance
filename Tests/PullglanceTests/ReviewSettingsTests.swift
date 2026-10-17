import Foundation
import Testing
@testable import Pullglance

@Suite struct ReviewSettingsTests {
    @Test func presetsComeFromTheBuiltJSON() {
        #expect(ReviewPresets.all.contains { $0.id == "js-unit" && $0.enabled })
        #expect(ReviewPresets.all.contains { $0.id == "js-stories" && !$0.enabled })
        #expect(ReviewSettings.default.presets["js-unit"] == true)
        #expect(ReviewSettings.default.presets["js-stories"] == false)
    }

    @Test func customGlobsIgnoreBlankAndCommentLines() {
        var s = ReviewSettings.default
        s.customGlobsText = "# generated\n**/*.pb.go\n\n  dist/** \n"
        #expect(s.customGlobs == ["**/*.pb.go", "dist/**"])
        let payload = s.scriptPayload
        #expect(payload["customGlobs"] as? [String] == ["**/*.pb.go", "dist/**"])
        #expect(payload["version"] as? Int == 1)
        #expect(payload["loadBeforeMark"] as? Bool == true)
    }

    @Test func roundTripsThroughDefaults() {
        let defaults = testDefaults()
        var s = ReviewSettings.default
        s.autoMark = true
        s.presets["go"] = false
        s.save(defaults)
        #expect(ReviewSettings.load(defaults) == s)
        #expect(ReviewSettings.load(testDefaults()) == .default)
    }

    @Test func settingsSavedBeforeThePillDecodeWithTheDefaultPosition() throws {
        let old = Data(#"{"presets":{"go":false},"customGlobsText":"","autoMark":true,"rememberCompare":true,"verify":true,"loadBeforeMark":true}"#.utf8)
        let decoded = try JSONDecoder().decode(ReviewSettings.self, from: old)
        #expect(decoded.filePill == .bottom)
        #expect(decoded.autoMark)
        var s = ReviewSettings.default
        s.filePill = .top
        let defaults = testDefaults()
        s.save(defaults)
        #expect(ReviewSettings.load(defaults).filePill == .top)
    }

    /// Viewed files leave the file tree unless the reader turns that off in the bar; settings saved before
    /// the switch existed hide them too.
    @Test func treeHidesViewedByDefaultAndTravelsToTheScript() throws {
        #expect(ReviewSettings.default.treeHidesViewed)
        #expect(ReviewSettings.default.scriptPayload["treeHidesViewed"] as? Bool == true)
        let old = Data(#"{"presets":{},"customGlobsText":"","autoMark":false,"rememberCompare":true,"verify":true,"loadBeforeMark":true}"#.utf8)
        #expect(try JSONDecoder().decode(ReviewSettings.self, from: old).treeHidesViewed)
        var s = ReviewSettings.default
        s.treeHidesViewed = false
        let defaults = testDefaults()
        s.save(defaults)
        #expect(ReviewSettings.load(defaults).treeHidesViewed == false)
        #expect(s.scriptPayload["treeHidesViewed"] as? Bool == false)
    }

    /// The window is a beta: off unless turned on, and settings saved before the flag existed stay off.
    @Test func theReviewWindowIsOffByDefaultAndForOlderSettings() throws {
        #expect(ReviewSettings.default.windowEnabled == false)
        let older = Data(#"{"presets":{},"customGlobsText":"","autoMark":false,"rememberCompare":true,"verify":true,"loadBeforeMark":true}"#.utf8)
        #expect(try JSONDecoder().decode(ReviewSettings.self, from: older).windowEnabled == false)
        var s = ReviewSettings.default
        s.windowEnabled = true
        let again = try JSONDecoder().decode(ReviewSettings.self, from: try JSONEncoder().encode(s))
        #expect(again.windowEnabled)
    }

    @Test func presetChoiceIsPerRepository() {
        let defaults = testDefaults()
        ReviewPresetChoice.preset("python").save(defaults, repo: "acme/web")
        #expect(ReviewPresetChoice.load(defaults, repo: "acme/web") == .preset("python"))
        #expect(ReviewPresetChoice.load(defaults, repo: "acme/api") == .auto)
        #expect(ruleIDs(for: .auto, settings: .default) == nil)
        #expect(ruleIDs(for: .preset("python"), settings: .default) == ["python"])
        #expect(ruleIDs(for: .custom, settings: .default) == ["custom"])
    }
}
