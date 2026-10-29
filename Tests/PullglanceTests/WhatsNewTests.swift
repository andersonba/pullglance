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
