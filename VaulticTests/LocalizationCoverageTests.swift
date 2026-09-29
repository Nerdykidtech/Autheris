import XCTest
@testable import Vaultic

/// Guards the translations the app ships.
///
/// Four String Catalogs ship from this repository, and all four are checked here:
/// `Vaultic/Localizable.xcstrings` for the app's own strings,
/// `Vaultic/InfoPlist.xcstrings` for the camera and Face ID prompts — the system
/// reads those from a table of their own, which is why they need a second file —
/// and the watch's `Localizable` and `InfoPlist` catalogs. Between them they cover
/// seven languages: English plus the six the store listing is already translated
/// into.
///
/// Every entry is marked `translated`. That says the strings are settled for this
/// release, not that a human has read them: the wording was produced by machine
/// translation and no native speaker has reviewed it, so what these tests are
/// worth is not that the wording is good. It is that the *shape* is right: every
/// string has an entry, every entry has all six languages, and no translation
/// quietly loses a placeholder or a plural form. Wording is for a reviewer;
/// structure is for a machine, and this is the machine.
///
/// Two of them reach outside the app to do that, deliberately.
///
/// `testEveryLocalizableLiteralInTheSourcesHasAnEntry` reads the Swift sources,
/// because a String Catalog only knows about the strings Xcode *extracted*. A
/// literal that never reached the extractor is not missing from the catalog — it
/// is invisible to it, and it ships as English with nothing to notice. That is not
/// hypothetical: six Mac Settings rows were in exactly that state while this was
/// written, because `actionRowLabel` took a `String`, and five of its six literal
/// arguments had no entry anywhere. The same shape hid the onboarding feature
/// titles, the accent-colour names, and every literal inside `#if os(macOS)` until
/// the catalog was synced from a Mac build as well as an iOS one.
///
/// The compiled-catalog tests read the built `Autheris.app` instead, because a
/// catalog full of translations proves nothing if the build never puts them in the
/// app — the catalog could be out of the target, or unreachable from the bundle.
/// The watch's own copy is checked the same way, but only when the host build
/// embedded it, which an iOS build does and a Mac build does not.
final class LocalizationCoverageTests: XCTestCase {

    // MARK: - What the app is expected to ship

    /// English is the source language; these are the six the listing is already
    /// translated into, and the app follows the listing.
    private static let translatedLanguages = ["es-ES", "fr-FR", "de-DE", "ja", "zh-Hans", "pt-BR"]

    /// Languages whose CLDR plural rules have a `one` category. Japanese and
    /// Simplified Chinese do not: `%lld 件のコード` reads the same for one and for
    /// many, and a `one` form there would never be selected.
    private static let languagesWithSingularPlurals: Set<String> = ["en", "es-ES", "fr-FR", "de-DE", "pt-BR"]

    /// The app's own catalog, which is the only one with plural entries and the
    /// only one the compiled-bundle comparisons resolve without a table name.
    private static let appCatalogPath = "Vaultic/Localizable.xcstrings"

    /// Every catalog that ships. A file that is in no target is invisible to all
    /// of this, so the list is the place to notice one going missing.
    private static let catalogPaths = [
        appCatalogPath,
        "Vaultic/InfoPlist.xcstrings",
        "VaulticWatch/Localizable.xcstrings",
        "VaulticWatch/InfoPlist.xcstrings",
    ]

    /// The directories scanned for localizable literals, each against its own
    /// catalog: a watch literal has to be found in the *watch's* catalog, and
    /// checking it against the app's would be the wrong question.
    private static let sourceRoots: [(sources: String, catalog: String)] = [
        ("Vaultic", appCatalogPath),
        ("VaulticWatch", "VaulticWatch/Localizable.xcstrings"),
    ]

    /// The `String` properties a view holds before `Text` can look anything up.
    /// Matched by *shape* rather than by name, for the same reason
    /// `BundledResourcesTests` matches by shape: a rename has to be caught too.
    private static let localizableCallPatterns = [
        "(?:Text|Button|Label|Toggle|Section|Link|Picker|LabeledContent|TextField|SecureField|navigationTitle|accessibilityLabel|accessibilityHint|alert|confirmationDialog)\\(\\s*\"((?:[^\"\\\\]|\\\\.)*)\"\\s*[,)]",
        "String\\(localized:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"",
        "[\\w.]+\\.(?:text|title) = \"((?:[^\"\\\\]|\\\\.)*)\"",
    ]

    // MARK: - Reading the catalog

    /// Derived from `#filePath`, which is the only way back to the sources from
    /// inside a test that runs in the app. It makes these tests a developer check
    /// rather than a shipped one — the app itself never needs the file.
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)      // …/VaulticTests/LocalizationCoverageTests.swift
            .deletingLastPathComponent()      // …/VaulticTests
            .deletingLastPathComponent()      // …/
    }

    private func loadCatalog(_ path: String) throws -> [String: [String: Any]] {
        let url = repositoryRoot.appendingPathComponent(path)
        let data = try Data(contentsOf: url)
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any],
            "\(path) is not a JSON object"
        )
        XCTAssertEqual(root["sourceLanguage"] as? String, "en", "\(path): the source language is English")
        let strings = try XCTUnwrap(root["strings"] as? [String: Any], "\(path) has no strings")
        let catalog = strings.compactMapValues { $0 as? [String: Any] }
        XCTAssertEqual(catalog.count, strings.count, "\(path): every entry should be an object")
        XCTAssertFalse(catalog.isEmpty, "\(path) has no entries")
        return catalog
    }

    /// A plain entry: exactly one string per language.
    private func stringUnit(_ entry: [String: Any], _ language: String) -> [String: Any]? {
        guard let localizations = entry["localizations"] as? [String: Any],
              let languageEntry = localizations[language] as? [String: Any] else { return nil }
        return languageEntry["stringUnit"] as? [String: Any]
    }

    private func value(_ entry: [String: Any], _ language: String) -> String? {
        stringUnit(entry, language)?["value"] as? String
    }

    /// A plural entry: one string per plural category, in the same language slot.
    private func pluralForms(_ entry: [String: Any], _ language: String) -> [String: String]? {
        guard let localizations = entry["localizations"] as? [String: Any],
              let languageEntry = localizations[language] as? [String: Any],
              let variations = languageEntry["variations"] as? [String: Any],
              let plural = variations["plural"] as? [String: Any] else { return nil }
        var forms: [String: String] = [:]
        for (category, form) in plural {
            guard let unit = (form as? [String: Any])?["stringUnit"] as? [String: Any],
                  let text = unit["value"] as? String else { return nil }
            forms[category] = text
        }
        return forms
    }

    /// Every string an entry carries for a language, whatever its shape.
    private func strings(_ entry: [String: Any], _ language: String) -> [String] {
        if let value = value(entry, language) { return [value] }
        if let forms = pluralForms(entry, language) { return forms.values.sorted() }
        return []
    }

    private func isPlural(_ entry: [String: Any]) -> Bool {
        Self.translatedLanguages.contains { pluralForms(entry, $0) != nil }
    }

    /// The `needs_review` / `translated` flags, which say whether a human has read
    /// the string. Nothing may be left at `new`, which means "not written yet".
    private func states(_ entry: [String: Any], _ language: String) -> [String] {
        var states: [String] = []
        if let state = stringUnit(entry, language)?["state"] as? String { states.append(state) }
        if let localizations = entry["localizations"] as? [String: Any],
           let languageEntry = localizations[language] as? [String: Any],
           let variations = languageEntry["variations"] as? [String: Any],
           let plural = variations["plural"] as? [String: Any] {
            for form in plural.values {
                if let state = (form as? [String: Any])?["stringUnit"] as? [String: Any],
                   let state = state["state"] as? String {
                    states.append(state)
                }
            }
        }
        return states
    }

    /// The placeholder types a string carries, with positional indices and length
    /// modifiers normalised away, so `%1$lld` and `%lld` compare equal. Counted
    /// rather than collected: a translation that drops one of two `%@` is the bug
    /// this exists to catch.
    private func placeholders(in string: String) -> [String] {
        let pattern = "%(?:\\d+\\$)?(lld|ld|d|@)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            XCTFail("bad placeholder pattern")
            return []
        }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        return regex.matches(in: string, range: range).compactMap { match in
            guard let range = Range(match.range(at: 1), in: string) else { return nil }
            return String(string[range])
        }.sorted()
    }

    // MARK: - The catalogs in the repository

    func testEveryEntryIsTranslatedIntoEveryLanguage() throws {
        for path in Self.catalogPaths {
            let catalog = try loadCatalog(path)
            for (key, entry) in catalog.sorted(by: { $0.key < $1.key }) {
                guard !(entry["shouldTranslate"] as? Bool == false) else { continue }
                for language in Self.translatedLanguages {
                    let strings = strings(entry, language)
                    XCTAssertFalse(strings.isEmpty, "\(path): \(language) has no entry for \"\(key)\"")
                    for string in strings {
                        XCTAssertFalse(string.isEmpty, "\(path): \(language) is empty for \"\(key)\"")
                    }
                }
            }
        }
    }

    func testNoEntryIsLeftWaitingForSomeoneToWriteIt() throws {
        for path in Self.catalogPaths {
            let catalog = try loadCatalog(path)
            for (key, entry) in catalog.sorted(by: { $0.key < $1.key }) {
                for language in Self.translatedLanguages {
                    for state in states(entry, language) {
                        XCTAssertNotEqual(
                            state, "new",
                            "\(path): \"\(key)\" is still untranslated in \(language) — `new` means "
                            + "nobody has written it, not that nobody has checked it"
                        )
                    }
                }
            }
        }
    }

    func testPluralEntriesDeclareTheCategoriesTheirLanguageNeeds() throws {
        for path in Self.catalogPaths {
            let catalog = try loadCatalog(path)
            let plurals = catalog.filter { isPlural($0.value) }
            if path == Self.appCatalogPath {
                // Only the app's own catalog has plurals to check; the Info.plist
                // and watch catalogs carry single strings, and a plural that
                // appeared in one of those would be worth a look.
                XCTAssertFalse(plurals.isEmpty, "\(path) should have plural entries to check")
            }

            for (key, entry) in plurals.sorted(by: { $0.key < $1.key }) {
                // A plural entry's key is what the app asks for, and it must offer
                // the number the category is chosen from.
                XCTAssertEqual(
                    placeholders(in: key), ["lld"],
                    "\(path): \"\(key)\" must take exactly one integer, or no plural rule can select from it"
                )
                for language in Self.translatedLanguages + ["en"] {
                    let forms = try XCTUnwrap(
                        pluralForms(entry, language),
                        "\(path): \"\(key)\" has no plural forms for \(language)"
                    )
                    XCTAssertNotNil(forms["other"], "\(path): \"\(key)\" needs an `other` form for \(language)")
                    if Self.languagesWithSingularPlurals.contains(language) {
                        XCTAssertNotNil(forms["one"], "\(path): \"\(key)\" needs a `one` form for \(language)")
                    } else {
                        XCTAssertNil(
                            forms["one"],
                            "\(path): \"\(key)\" has a `one` form for \(language), where CLDR has no such "
                            + "category — it would never be selected, so it is a form nobody will ever see"
                        )
                    }
                }
            }
        }
    }

    func testTranslationsKeepEveryPlaceholderTheKeyHas() throws {
        for path in Self.catalogPaths {
            let catalog = try loadCatalog(path)
            for (key, entry) in catalog.sorted(by: { $0.key < $1.key }) {
                let expected = placeholders(in: key)
                guard !expected.isEmpty else { continue }
                for language in Self.translatedLanguages {
                    for string in strings(entry, language) {
                        XCTAssertEqual(
                            placeholders(in: string), expected,
                            "\(path): \(language) for \"\(key)\" is \"\(string)\": the placeholders "
                            + "do not match the key"
                        )
                    }
                }
            }
        }
    }

    func testTheProductNameIsNotTranslated() throws {
        let catalog = try loadCatalog(Self.appCatalogPath)
        let autheris = try XCTUnwrap(catalog["Autheris"], "the product name should be in the catalog")
        XCTAssertEqual(autheris["shouldTranslate"] as? Bool, false, "Autheris is a name, not a word")
        XCTAssertNil(autheris["localizations"], "a name that is never translated needs no translations")
    }

    /// The same rule as the product name, anywhere it appears — including the two
    /// `Info.plist` keys that carry it. A `shouldTranslate` of `false` under a pile
    /// of translations is a contradiction: it says "leave this alone" while
    /// offering something to use instead.
    func testEntriesThatOptOutOfTranslationCarryNoTranslations() throws {
        for path in Self.catalogPaths {
            let catalog = try loadCatalog(path)
            for (key, entry) in catalog.sorted(by: { $0.key < $1.key }) {
                guard entry["shouldTranslate"] as? Bool == false else { continue }
                XCTAssertNil(
                    entry["localizations"],
                    "\(path): \"\(key)\" opts out of translation, so it needs no translations"
                )
            }
        }
    }

    // MARK: - The catalogs as the app actually ships them

    private func appBundle() throws -> Bundle {
        // `Bundle(for:)` rather than `Bundle.main`: the test host is the app, but
        // asking for the app's own type says that out loud.
        try XCTUnwrap(Bundle(for: OTPDataStore.self) as Bundle?, "no host bundle")
    }

    private func bundle(for language: String) throws -> Bundle {
        let app = try appBundle()
        let path = try XCTUnwrap(
            app.path(forResource: language, ofType: "lproj"),
            "\(language).lproj is missing from the app bundle — the catalog is not "
            + "reaching the build, so the app runs English in \(language)"
        )
        return try XCTUnwrap(Bundle(path: path), "\(language).lproj is not a bundle")
    }

    /// The watch app inside the host app, when there is one.
    ///
    /// The Mac build has none: the "Embed Watch Content" phase carries
    /// `platformFilters = (ios, )`, so `Autheris.app` on the Mac has no `Watch/`
    /// directory at all. Returning nil there is the honest answer rather than a
    /// failure, and it is why the watch's strings are only checked by the run that
    /// actually embedded them.
    private func watchBundle() throws -> Bundle? {
        let watch = try appBundle().bundleURL.appendingPathComponent("Watch/Autheris.app")
        guard FileManager.default.fileExists(atPath: watch.path) else { return nil }
        return try XCTUnwrap(Bundle(url: watch), "\(watch.path) is not a bundle")
    }

    func testEveryTranslatedLanguageReachesTheAppBundle() throws {
        for language in Self.translatedLanguages {
            let bundle = try bundle(for: language)
            XCTAssertFalse(
                bundle.localizedString(forKey: "Cancel", value: nil, table: nil).isEmpty,
                "\(language) resolved nothing"
            )
        }
    }

    /// The strength of this one is that it compares the *built* strings against the
    /// catalog rather than against a copy of the wording kept in the test: it fails
    /// if a translation does not reach the bundle, and it keeps working when the
    /// wording changes.
    func testTheStringsInTheAppAreTheOnesInTheCatalog() throws {
        let catalog = try loadCatalog(Self.appCatalogPath)
        for language in Self.translatedLanguages {
            let bundle = try bundle(for: language)
            for (key, entry) in catalog.sorted(by: { $0.key < $1.key }) {
                guard !isPlural(entry), let expected = value(entry, language) else { continue }
                XCTAssertEqual(
                    bundle.localizedString(forKey: key, value: nil, table: nil), expected,
                    "the compiled \(language) string for \"\(key)\" is not the catalog's"
                )
            }
        }
    }

    /// The `Info.plist` prompts are a second table, and a table is exactly the
    /// kind of thing that can be in the catalog and still miss the bundle — the
    /// camera and Face ID prompts read this one by name, so a lookup that never
    /// finds it hands the user the English from the build setting instead.
    func testThePrivacyPromptsInTheAppAreTheOnesInTheCatalog() throws {
        let catalog = try loadCatalog("Vaultic/InfoPlist.xcstrings")
        for language in Self.translatedLanguages {
            let bundle = try bundle(for: language)
            for (key, entry) in catalog.sorted(by: { $0.key < $1.key }) {
                guard let expected = value(entry, language) else { continue }
                XCTAssertEqual(
                    bundle.localizedString(forKey: key, value: nil, table: "InfoPlist"), expected,
                    "the compiled \(language) Info.plist string for \"\(key)\" is not the catalog's"
                )
            }
        }
    }

    func testTheWatchStringsReachTheWatchAppWhenItIsEmbedded() throws {
        guard let watch = try watchBundle() else { return }
        let catalog = try loadCatalog("VaulticWatch/Localizable.xcstrings")
        for language in Self.translatedLanguages {
            let path = try XCTUnwrap(
                watch.path(forResource: language, ofType: "lproj"),
                "the watch app has no \(language).lproj — the watch catalog is not "
                + "reaching the build, so the watch runs English in \(language)"
            )
            let bundle = try XCTUnwrap(Bundle(path: path), "the watch's \(language).lproj is not a bundle")
            for (key, entry) in catalog.sorted(by: { $0.key < $1.key }) {
                guard let expected = value(entry, language) else { continue }
                XCTAssertEqual(
                    bundle.localizedString(forKey: key, value: nil, table: nil), expected,
                    "the compiled \(language) watch string for \"\(key)\" is not the catalog's"
                )
            }
        }
    }

    func testPluralFormsResolveThroughTheCompiledCatalog() throws {
        // French is the interesting case: `one` covers 0 and 1, and the two forms
        // differ. Japanese exercises the other half — one form, no `one` category.
        let french = try bundle(for: "fr-FR")
        let frenchFormat = french.localizedString(forKey: "Delete %lld Codes", value: nil, table: nil)
        XCTAssertEqual(
            String(format: frenchFormat, locale: Locale(identifier: "fr-FR"), arguments: [1]),
            "Supprimer 1 code"
        )
        XCTAssertEqual(
            String(format: frenchFormat, locale: Locale(identifier: "fr-FR"), arguments: [3]),
            "Supprimer 3 codes"
        )

        let japanese = try bundle(for: "ja")
        let japaneseFormat = japanese.localizedString(forKey: "Delete %lld Codes", value: nil, table: nil)
        for count in [1, 3] {
            XCTAssertEqual(
                String(format: japaneseFormat, locale: Locale(identifier: "ja"), arguments: [count]),
                "\(count) 件のコードを削除"
            )
        }
    }

    // MARK: - The sources the catalog is built from

    /// The one test that can catch a string the extractor never saw. It reads the
    /// sources rather than the catalog, so a `Text("...")` that no build has been
    /// synced for yet is a failure here instead of English in the shipped app.
    ///
    /// It looks only at what it can be sure about: literals with no interpolation,
    /// on one line. An interpolated literal cannot be matched to a key without
    /// type-checking the interpolation, and guessing at it would produce a test
    /// that cries wolf until someone deletes it. The same fence leaves the watch's
    /// five strings out of reach — they arrive through ternaries, one of them
    /// multi-line — so what this half of the scan guards is the next literal
    /// someone adds there, not the five that are already in the catalog.
    func testEveryLocalizableLiteralInTheSourcesHasAnEntry() throws {
        var checked = 0
        for (root, catalogPath) in Self.sourceRoots {
            let sources = repositoryRoot.appendingPathComponent(root)
            let files = try XCTUnwrap(
                FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?.allObjects
                    as? [URL],
                "could not walk \(sources.path)"
            ).filter { $0.pathExtension == "swift" }
            XCTAssertFalse(files.isEmpty, "no sources found under \(sources.path)")

            let catalog = try loadCatalog(catalogPath)
            let patterns = Self.localizableCallPatterns.compactMap {
                try? NSRegularExpression(pattern: $0)
            }
            XCTAssertEqual(patterns.count, Self.localizableCallPatterns.count, "bad pattern")

            for file in files {
                let source = try String(contentsOf: file, encoding: .utf8)
                let range = NSRange(source.startIndex..<source.endIndex, in: source)
                for pattern in patterns {
                    for match in pattern.matches(in: source, range: range) {
                        guard let matchRange = Range(match.range(at: 1), in: source) else { continue }
                        let literal = String(source[matchRange])
                        // Interpolated and multi-line literals are out of reach; an
                        // empty match is the `"""` of a multi-line literal opening.
                        guard !literal.isEmpty, !literal.contains("\\("), !literal.contains("\n") else { continue }
                        let key = literal
                            .replacingOccurrences(of: "\\\"", with: "\"")
                            .replacingOccurrences(of: "\\\\", with: "\\")
                        checked += 1
                        XCTAssertNotNil(
                            catalog[key],
                            "\(file.lastPathComponent) has a localizable literal with no entry in "
                            + "\(catalogPath): \"\(key)\". Build for iOS, macOS and watchOS, then run "
                            + "`xcrun xcstringstool sync \(catalogPath) --stringsdata …`"
                        )
                    }
                }
            }
        }
        XCTAssertGreaterThan(checked, 200, "the scan found almost nothing, so it is not really scanning")
    }
}
