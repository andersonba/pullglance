import Foundation
import Testing
@testable import Pullglance

@Suite struct OnboardingStepTests {
    @Test func fiveStepsInTheAgreedOrder() {
        let steps = OnboardingStep.all
        #expect(steps.count == 5)
        #expect(Set(steps.map(\.id)).count == 5)
        #expect(steps[1].content == .requirements)
        #expect(steps.filter { $0.content == .requirements }.count == 1)
        #expect(steps.filter { $0.content == .notifications }.count == 1)
        #expect(steps.last?.content == .notifications)
        #expect(steps[1].pose == .waiting)
        #expect(steps.last?.pose == .pointing)
        #expect(OnboardingStep.index(of: "gh") == 1)
        #expect(OnboardingStep.index(of: "nope") == nil)
    }
}
