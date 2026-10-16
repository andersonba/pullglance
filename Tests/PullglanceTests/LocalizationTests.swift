import Foundation
import Testing
@testable import Pullglance

@Suite struct LocalizationTests {
    /// The legacy SwiftPM build lowercases the folder (pt-br.lproj); the Swift Build one keeps pt-BR.lproj.
    private func bundle(_ locale: String) throws -> Bundle {
        let path = try #require(Bundle.app.paths(forResourcesOfType: "lproj", inDirectory: nil).first {
            URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent.lowercased() == locale
        })
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
        let ptFiles = pt.localizedString(forKey: "%lld files", value: nil, table: nil)
        #expect(String.localizedStringWithFormat(ptFiles, 1) == "1 arquivo")
        #expect(String.localizedStringWithFormat(ptFiles, 3) == "3 arquivos")
        let enRepos = en.localizedString(forKey: "%lld repos", value: nil, table: nil)
        #expect(String.localizedStringWithFormat(enRepos, 1) == "1 repo")
        #expect(String.localizedStringWithFormat(enRepos, 2) == "2 repos")
        let enBack = en.localizedString(forKey: "%lld pull requests are back in their sections", value: nil, table: nil)
        #expect(String.localizedStringWithFormat(enBack, 1) == "1 pull request is back in its section")
        #expect(String.localizedStringWithFormat(enBack, 2) == "2 pull requests are back in their sections")
    }

    /// Words that only inflect in Portuguese: English keeps them in the strings file, Portuguese in the plurals.
    @Test func portugueseOnlyPlurals() throws {
        let pt = try bundle("pt-br")
        func resolved(_ key: String, _ counts: Int...) -> String {
            let format = pt.localizedString(forKey: key, value: nil, table: nil)
            return counts.count == 1 ? String.localizedStringWithFormat(format, counts[0]) : String.localizedStringWithFormat(format, counts[0], counts[1])
        }
        #expect(resolved("%lld open", 1) == "1 aberto")
        #expect(resolved("%lld open", 5) == "5 abertos")
        #expect(resolved("%lld hidden", 1) == "1 oculto")
        #expect(resolved("%lld chosen", 1) == "1 escolhido")
        #expect(resolved("%lld marked", 1) == "1 marcado")
        #expect(resolved("%lld unmarked", 2) == "2 desmarcados")
        #expect(resolved("%lld marked · %lld failed", 1, 1) == "1 marcado · 1 falhou")
        #expect(resolved("%lld marked · %lld failed", 3, 2) == "3 marcados · 2 falharam")
        #expect(resolved("Quick · %lld files", 1) == "Rápido · 1 arquivo")
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
