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
