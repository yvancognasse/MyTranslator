import Foundation
import NaturalLanguage
import Translation

func env(_ key: String, _ fallback: String = "") -> String {
    ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? fallback
}

func envTimeoutSeconds() -> UInt64 {
    let raw = env("MYTRANSLATOR_TIMEOUT_SECONDS", "20")
    return UInt64(raw) ?? 20
}

func languageCode(_ language: String) -> String {
    let key = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let map: [String: String] = [
        "en": "en",
        "en-au": "en",
        "en-ca": "en",
        "en-gb": "en",
        "en-ie": "en",
        "en-in": "en",
        "en-nz": "en",
        "en-sg": "en",
        "en-za": "en",
        "fr": "fr",
        "fr-ca": "fr",
        "es": "es",
        "es-mx": "es",
        "es-us": "es",
        "de": "de",
        "de-ch": "de",
        "it": "it",
        "it-ch": "it",
        "pt": "pt",
        "pt-pt": "pt",
        "nl": "nl",
        "ru": "ru",
        "zh": "zh-Hans",
        "zh-hk": "zh-Hant",
        "zh-hans": "zh-Hans",
        "zh-hant": "zh-Hant",
        "zh-tw": "zh-Hant",
        "ja": "ja",
        "ko": "ko",
        "ar": "ar",
        "hi": "hi",
        "bn": "bn",
        "ur": "ur",
        "tr": "tr",
        "pl": "pl",
        "sv": "sv",
        "no": "no",
        "nb": "nb",
        "da": "da",
        "fi": "fi",
        "el": "el",
        "he": "he",
        "th": "th",
        "vi": "vi",
        "id": "id",
        "ms": "ms",
        "cs": "cs",
        "ro": "ro",
        "english": "en",
        "french": "fr",
        "spanish": "es",
        "german": "de",
        "italian": "it",
        "portuguese": "pt",
        "dutch": "nl",
        "russian": "ru",
        "simplified chinese": "zh-Hans",
        "traditional chinese": "zh-Hant",
        "japanese": "ja",
        "korean": "ko",
        "arabic": "ar",
        "hindi": "hi",
        "bengali": "bn",
        "urdu": "ur",
        "turkish": "tr",
        "polish": "pl",
        "swedish": "sv",
        "norwegian": "no",
        "danish": "da",
        "finnish": "fi",
        "greek": "el",
        "hebrew": "he",
        "thai": "th",
        "vietnamese": "vi",
        "indonesian": "id",
        "malay": "ms",
        "czech": "cs",
        "romanian": "ro",
        "anglais": "en",
        "français": "fr",
        "francais": "fr",
        "espagnol": "es",
        "allemand": "de",
        "italien": "it",
        "portugais": "pt",
        "néerlandais": "nl",
        "neerlandais": "nl",
        "russe": "ru",
        "chinois": "zh-Hans",
        "japonais": "ja",
        "coréen": "ko",
        "coreen": "ko",
        "arabe": "ar",
        "turc": "tr",
        "polonais": "pl",
        "suédois": "sv",
        "suedois": "sv",
        "norvégien bokmål": "nb",
        "norvegien bokmal": "nb",
        "danois": "da",
        "finnois": "fi",
        "grec": "el",
        "hébreu": "he",
        "hebreu": "he",
        "thaï": "th",
        "vietnamien": "vi",
        "indonésien": "id",
        "indonesien": "id",
        "roumain": "ro"
    ]
    return map[key] ?? key
}

func languageName(_ code: String) -> String {
    let map: [String: String] = [
        "en": "English",
        "fr": "French",
        "es": "Spanish",
        "de": "German",
        "it": "Italian",
        "pt": "Portuguese",
        "nl": "Dutch",
        "ru": "Russian",
        "zh-Hans": "Simplified Chinese",
        "zh-Hant": "Traditional Chinese",
        "ja": "Japanese",
        "ko": "Korean",
        "ar": "Arabic",
        "hi": "Hindi",
        "bn": "Bengali",
        "ur": "Urdu",
        "tr": "Turkish",
        "uk": "Ukrainian",
        "pl": "Polish",
        "sv": "Swedish",
        "no": "Norwegian",
        "nb": "Norwegian Bokmal",
        "da": "Danish",
        "fi": "Finnish",
        "el": "Greek",
        "he": "Hebrew",
        "th": "Thai",
        "vi": "Vietnamese",
        "id": "Indonesian",
        "ms": "Malay",
        "cs": "Czech",
        "ro": "Romanian"
    ]
    return map[code] ?? Locale.current.localizedString(forLanguageCode: code) ?? code
}

func distinctSupportedLanguageCode(_ identifier: String) -> String {
    let base = identifier.split(separator: "-").first.map(String.init)?.lowercased() ?? identifier.lowercased()
    // Apple lists Chinese regions separately; the Settings list represents one language.
    return base == "zh" ? "zh-Hans" : base
}

func detectedLanguageCode(_ text: String) -> String? {
    let recognizer = NLLanguageRecognizer()
    recognizer.processString(text)
    guard let language = recognizer.dominantLanguage else {
        return nil
    }
    return language.rawValue
}

func translationPair(for text: String) -> (source: String, target: String) {
    let primaryLanguage = languageCode(env("MYTRANSLATOR_SOURCE_LANGUAGE", "fr"))
    let translationLanguage = languageCode(env("MYTRANSLATOR_TARGET_LANGUAGE", "en"))

    if let detected = detectedLanguageCode(text) {
        if detected == primaryLanguage {
            return (primaryLanguage, translationLanguage)
        }
        return (detected, primaryLanguage)
    }

    return (translationLanguage, primaryLanguage)
}

@main
struct Main {
    static func main() async {
        if CommandLine.arguments.contains("--supported-languages") {
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                exit(0)
            }
            let availability = LanguageAvailability()
            let supported = await availability.supportedLanguages
            let uniqueCodes = Set(supported.map { distinctSupportedLanguageCode($0.minimalIdentifier) })
            for code in uniqueCodes.sorted() {
                let name = code == "zh-Hans" ? "Chinese" : languageName(code)
                print("\(code)\t\(name)")
            }
            return
        }
        if CommandLine.arguments.contains("--languages") {
            let languageTask = Task { () -> [String] in
                let availability = LanguageAvailability()
                let supported = await availability.supportedLanguages
                var installed: [String: String] = [:]
                for language in supported {
                    let status = await availability.status(from: language, to: nil)
                    if status == .installed {
                        let code = languageCode(language.minimalIdentifier)
                        installed[code] = languageName(code)
                    }
                }
                return installed
                    .map { "\($0.key)\t\($0.value)" }
                    .sorted { lhs, rhs in
                        let leftLabel = lhs.split(separator: "\t", maxSplits: 1).last ?? ""
                        let rightLabel = rhs.split(separator: "\t", maxSplits: 1).last ?? ""
                        return String(leftLabel).localizedCaseInsensitiveCompare(String(rightLabel)) == .orderedAscending
                    }
            }
            Task {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                if !languageTask.isCancelled {
                    exit(0)
                }
            }
            let installed = await languageTask.value
            for language in installed {
                print(language)
            }
            return
        }

        let input = FileHandle.standardInput.readDataToEndOfFile()
        guard let raw = String(data: input, encoding: .utf8), !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let leadingCount = raw.prefix { $0.isWhitespace }.count
        let trailingCount = raw.reversed().prefix { $0.isWhitespace }.count
        let leading = String(raw.prefix(leadingCount))
        let trailing = trailingCount > 0 ? String(raw.suffix(trailingCount)) : ""
        let coreEnd = raw.index(raw.endIndex, offsetBy: -trailingCount)
        let coreStart = raw.index(raw.startIndex, offsetBy: leadingCount)
        let core = String(raw[coreStart..<coreEnd])
        let timeoutSeconds = envTimeoutSeconds()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .seconds(Int(timeoutSeconds))) {
            fputs("Local Apple translation timed out after \(timeoutSeconds) seconds.\n", stderr)
            fflush(stderr)
            exit(124)
        }

        let pair = translationPair(for: core)
        let session = TranslationSession(
            installedSource: Locale.Language(identifier: pair.source),
            target: Locale.Language(identifier: pair.target)
        )

        do {
            try await session.prepareTranslation()
            let response = try await session.translate(core)
            let translated = response.targetText
            print("\(leading)\(translated)\(trailing)", terminator: "")
        } catch {
            fputs("Local Apple translation failed: \(error)\n", stderr)
            exit(1)
        }
    }
}
