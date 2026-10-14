import Testing
@testable import Pullglance

/// "+24 −44" on the row: essential at a glance, abbreviated once the numbers get long.
@Suite struct DiffSizeTests {
    @Test func formatsAdditionsAndDeletions() {
        #expect(diffSizeText(additions: 24, deletions: 44) == "+24 −44")
        #expect(diffSizeText(additions: 0, deletions: 0) == "+0 −0")
        #expect(diffSizeText(additions: nil, deletions: nil) == nil, "unknown size shows nothing")
    }

    @Test func abbreviatesThousands() {
        #expect(abbreviated(999) == "999")
        #expect(abbreviated(1_000) == "1k")
        #expect(abbreviated(1_234) == "1.2k")
        #expect(abbreviated(9_950) == "10k")
        #expect(abbreviated(12_345) == "12k")
        #expect(abbreviated(1_200_000) == "1.2m")
        #expect(diffSizeText(additions: 19_208, deletions: 70) == "+19k −70")
    }
}
