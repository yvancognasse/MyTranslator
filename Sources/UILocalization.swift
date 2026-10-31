import Foundation

enum UILocalization {
    private struct Catalog: Decodable {
        let languages: [String]
        let strings: [String: [String]]
    }

    private static let catalog: Catalog? = {
        guard let path = Bundle.main.path(forResource: "InterfaceLocalizations", ofType: "json"),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let value = try? JSONDecoder().decode(Catalog.self, from: data) else {
            return nil
        }
        return value
    }()

    static var currentLanguage: String {
        UserDefaults.standard.string(forKey: "MYTRANSLATOR_SOURCE_LANGUAGE") ?? "fr"
    }

    static func text(_ english: String, language: String? = nil) -> String {
        let code = language ?? currentLanguage
        guard let catalog,
              let languageIndex = catalog.languages.firstIndex(of: code),
              let values = catalog.strings[english],
              values.indices.contains(languageIndex),
              !values[languageIndex].isEmpty else {
            return english
        }
        return values[languageIndex]
    }
}
