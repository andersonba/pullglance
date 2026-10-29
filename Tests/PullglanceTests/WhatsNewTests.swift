import Foundation
import Testing
@testable import Pullglance

@Suite struct StepLocalizationTests {
    /// Step titles and texts go through LocalizedStringKey, invisible to LocalizationCoverageTests.
    @Test func everyStepKeyExistsInBothLanguages() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for lang in ["en", "pt-BR"] {
            let table = try String(contentsOf: repo.appendingPathComponent("Sources/Pullglance/Resources/\(lang).lproj/Localizable.strings"), encoding: .utf8)
            for key in OnboardingStep.localizationKeys(of: OnboardingStep.all) {
                #expect(table.contains("\"\(key)\" = "), "\(lang) lacks \(key)")
            }
        }
    }
}

@Suite struct VersionCompareTests {
    @Test func dottedNumbersNotStrings() {
        #expect(compareVersions("0.10.0", "0.9.0") == .orderedDescending)
        #expect(compareVersions("0.6.0", "0.6.0") == .orderedSame)
        #expect(compareVersions("0.6.0", "0.6.1") == .orderedAscending)
    }

    /// `dev`, a short version, a suffix: never a crash, and `dev` is older than everything.
    @Test func oddVersionsCompareWithoutCrashing() {
        #expect(compareVersions("dev", "0.1.0") == .orderedAscending)
        #expect(compareVersions("0.6", "0.6.0") == .orderedSame)
        #expect(compareVersions("0.6.0-beta", "0.6.0") == .orderedSame)
    }
}

@Suite struct WhatsNewStepTests {
    @Test func theScreensAreTaggedAndOrderedNewestReleaseFirst() {
        let all = WhatsNewStep.all
        #expect(all.allSatisfy { $0.version != nil })
        #expect(all.map(\.id) == ["watch", "deskKeys", "handoff", "stacks", "more-0.6.0", "assigned", "keyboard"])
        #expect(all.map(\.version) == ["0.6.0", "0.6.0", "0.6.0", "0.6.0", "0.6.0", "0.5.0", "0.3.0"])
        #expect(all.first { $0.id == "more-0.6.0" }?.tryIt == .openURL(URL(string: "https://github.com/andersonba/pullglance/releases/tag/v0.6.0")!))
    }

    @Test func dueIsEverythingNewerThanSeen() {
        #expect(WhatsNewStep.due(after: nil).count == 7)
        #expect(WhatsNewStep.due(after: "0.5.0").map(\.id) == ["watch", "deskKeys", "handoff", "stacks", "more-0.6.0"])
        #expect(WhatsNewStep.due(after: "0.4.0").map(\.id).last == "assigned")
        #expect(WhatsNewStep.due(after: "0.6.0").isEmpty)
        #expect(WhatsNewStep.latest().map(\.id) == ["watch", "deskKeys", "handoff", "stacks", "more-0.6.0"])
    }

    @Test func everyTourKeyExistsInBothLanguages() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for lang in ["en", "pt-BR"] {
            let table = try String(contentsOf: repo.appendingPathComponent("Sources/Pullglance/Resources/\(lang).lproj/Localizable.strings"), encoding: .utf8)
            for key in OnboardingStep.localizationKeys(of: WhatsNewStep.all) { #expect(table.contains("\"\(key)\" = "), "\(lang) lacks \(key)") }
        }
    }
}

@MainActor @Suite struct WhatsNewProgressTests {
    @Test func dueOnceAfterAnUpdate() {
        let defaults = testDefaults()
        let progress = WhatsNewProgress(defaults: defaults)
        #expect(progress.isDue(current: "0.6.0"), "never seen, screens exist")
        progress.markSeen(version: "0.6.0")
        #expect(WhatsNewProgress(defaults: defaults).isDue(current: "0.6.0") == false)
    }

    @Test func aReleaseWithoutScreensOpensNothing() {
        let defaults = testDefaults()
        let progress = WhatsNewProgress(defaults: defaults)
        progress.markSeen(version: "0.6.0")
        #expect(progress.isDue(current: "0.6.1") == false)
        #expect(progress.isDue(current: "0.7.0") == false, "no 0.7.0 screens yet")
    }

    @Test func devNeverSeesTheTour() {
        #expect(WhatsNewProgress(defaults: testDefaults()).isDue(current: "dev") == false)
    }

    /// A newcomer finishes the welcome on 0.6.0: the tour must not then show them 0.6.0's screens.
    @Test func completingTheWelcomeMarksTheTourSeen() {
        let defaults = testDefaults()
        OnboardingProgress(defaults: defaults).markCompleted(version: "0.6.0")
        #expect(WhatsNewProgress(defaults: defaults).seenVersion == "0.6.0")
        #expect(WhatsNewProgress(defaults: defaults).isDue(current: "0.6.0") == false)
    }
}
