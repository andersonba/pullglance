import Foundation
import Testing
@testable import Pullglance

@Suite struct LocalizationTests {
    private func bundle(_ locale: String) throws -> Bundle {
        let path = try #require(Bundle.app.path(forResource: locale, ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    @Test func portugueseTranslationsExist() throws {
        let pt = try bundle("pt-br")
        #expect(pt.localizedString(forKey: "Needs action", value: nil, table: nil) == "Precisa de ação")
        #expect(pt.localizedString(forKey: "To review", value: nil, table: nil) == "Para revisar")
        #expect(pt.localizedString(forKey: "Quit", value: nil, table: nil) == "Sair")
    }

    @Test func pluralsResolveInBothLanguages() throws {
        let en = try bundle("en")
        let pt = try bundle("pt-br")
        let enFormat = en.localizedString(forKey: "%lld open threads", value: nil, table: nil)
        let ptFormat = pt.localizedString(forKey: "%lld open threads", value: nil, table: nil)
        #expect(String.localizedStringWithFormat(enFormat, 1) == "1 open thread")
        #expect(String.localizedStringWithFormat(enFormat, 4) == "4 open threads")
        #expect(String.localizedStringWithFormat(ptFormat, 1) == "1 thread aberta")
        #expect(String.localizedStringWithFormat(ptFormat, 4) == "4 threads abertas")
    }

    /// Every key in English must have a Portuguese entry, so a new string cannot ship untranslated.
    @Test func everyEnglishKeyHasPortuguese() throws {
        let en = try bundle("en")
        let pt = try bundle("pt-br")
        let enURL = try #require(en.url(forResource: "Localizable", withExtension: "strings"))
        let ptURL = try #require(pt.url(forResource: "Localizable", withExtension: "strings"))
        let enKeys = Set(try #require(NSDictionary(contentsOf: enURL) as? [String: String]).keys)
        let ptKeys = Set(try #require(NSDictionary(contentsOf: ptURL) as? [String: String]).keys)
        #expect(enKeys.subtracting(ptKeys).isEmpty, "missing pt-BR: \(enKeys.subtracting(ptKeys).sorted())")
    }
}
