# Development

For anyone building or changing Autheris: the test suite, the localisation tooling, and the one way developer material can reach the app bundle.

# Tests

`VaulticTests` (XCTest) covers the logic that is easy to get wrong and cheap to assert: the iCloud conflict-resolution rules, the tombstone and Recently-Deleted bookkeeping, pinned-first ordering and drag-to-reorder, `OTPCode`'s backward-compatible decoding, the mirrored preferences, the privacy-shield rules, the phone↔watch payload contract, and `BackupCrypto`. Each of those rule sets lives in a pure, dependency-free type — `SyncMergeEngine`, `SyncTombstoneStore`, `TrashBin`, `TokenOrdering`, `AppPreferences`, `PrivacyShield`, `WatchTokenPayload` — precisely so it can be asserted without a simulator.

`VaulticTests/OTPGeneratorTests.swift` checks both code kinds against the published vectors rather than against themselves: RFC 6238 Appendix B for the time-based ones and RFC 4226 Appendix D for the counter-based ones, plus a case that pins the *seam* between them — the time-based code for the instant in counter N's window must equal the counter-based code for N, for every algorithm, digit count and period. `VaulticTests/OTPAuthURLParserTests.swift` holds the parser, including the host cases that used to be wrong: an `otpauth://hotp/` URL is counter-based and a `counter` on an `otpauth://totp/` one is ignored, and a counter larger than the iCloud field can hold is clamped rather than truncated.

`VaulticTests/WatchTokenPayloadTests.swift` is the exception worth naming: the phone app and the watch app are separate binaries that can be at **different versions**, so the cases that matter there are the ones where they disagree — a payload from a build that knows a newer format, a list arriving out of order, an empty list that has to mean "you have no codes" rather than "nothing has arrived".

```bash
xcodebuild test -project Vaultic.xcodeproj -scheme Vaultic \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max'
```

On a Mac the same suite runs natively if you pass signing:

```bash
xcodebuild test -project Vaultic.xcodeproj -scheme Vaultic \
  -destination 'platform=macOS' -allowProvisioningUpdates
```

Or press ⌘U in Xcode. The shared `Vaultic` scheme's Test action runs the whole `VaulticTests` target, which is hosted by the app because the tests use `@testable import Vaultic`. Note that the macOS run needs a real Mac provisioning profile rather than `CODE_SIGNING_ALLOWED=NO`: the CloudKit container is created eagerly at launch, and CloudKit aborts the process when `com.apple.developer.icloud-services` is missing, which takes the test host down with it.

The conflict-resolution cases live in `VaulticTests/SyncMergeEngineTests.swift`. They are deterministic because `SyncMergeEngine.merge` is pure by construction — no I/O and no clock reads (`now` and `tombstoneRetention` are parameters) — so each case pins both rather than reading the real clock. The rules they assert:

| Case | Expected |
| --- | --- |
| Local token, empty cloud | Token is uploaded; nothing adopted |
| Remote-only token | Adopted and appended, *not* echoed back |
| Remote edit newer | Adopted; nothing uploaded |
| Local edit newer | Uploaded; remote not adopted |
| Identical content | No uploads, no adoption |
| Remote tombstone, local token | Token removed locally, tombstone remembered |
| Local tombstone newer than a remote edit | Tombstone uploaded; token not resurrected |
| Local edit newer than a remote tombstone | Live record re-uploaded; token survives |
| Equal timestamps, different content | Both devices converge on the same winner |
| Token persisted before sync existed | Decodes with `modifiedAt == .distantPast` and loses to a dated remote edit |
| Tombstone older than 30 days | Not uploaded, dropped locally, and ignored when seen remotely |
| Round-trip of the previous outcome | No further work (fixed point) |

`OTPCode`'s hand-written `init(from:)` is what keeps pre-sync JSON decodable; `VaulticTests/OTPCodeCodableTests.swift` holds that case, so keep it passing whenever that type changes. `VaulticTests/BackupCryptoTests.swift` additionally pins the `.autheris` envelope against wrong passwords, tampered ciphertext, and a tampered salt.

# Localization

The app ships in seven languages: English, Spanish, French, German, Japanese, Simplified Chinese and Brazilian Portuguese. Those are the six the App Store listing is already translated into (`metadata/`), so the app follows the listing rather than the other way round — a language offered in the store is one the app should speak.

Everything the app says lives in a String Catalog. Xcode's extractor fills them from the sources; nothing in the app calls `NSLocalizedString` by hand.

| Catalog | What it carries |
| --- | --- |
| `Vaultic/Localizable.xcstrings` | everything the app's own views say |
| `Vaultic/InfoPlist.xcstrings` | the camera and Face ID prompts |
| `VaulticWatch/Localizable.xcstrings` | everything the watch says |
| `VaulticWatch/InfoPlist.xcstrings` | the watch's bundle name |

`InfoPlist` is a second *table*, not a second file's worth of the same thing: the system reads a privacy prompt out of `InfoPlist.strings`, so the camera and Face ID copy has to sit under those keys or nothing ever looks it up. There is one per target for the same reason there is one per table — the watch has a bundle of its own.

## Every entry says `translated`, and nobody has read one

`translated` is what the catalog owes a shipping build: it means the strings are settled, not that a human has checked them. The wording came out of machine translation and no native speaker has reviewed it, so the flag is a narrower claim than its name suggests — the App Store listing in `metadata/` is the only copy of this text a translator has actually touched. Reading the four catalogs before release is still what would catch a bad translation; the state itself will not tell you which language to look at. A language is not finished until its entries say `translated`, and all six do.

## Where the languages are declared

Two places, and they have to agree:

| Place | What it carries |
| --- | --- |
| `knownRegions` in `Vaultic.xcodeproj/project.pbxproj` | `en, Base, ja, es, zh-Hans, pt-BR, de, fr` |
| the four catalogs above | the per-language strings themselves |

Those are the **Xcode** language codes, not the App Store Connect ones: `es`, `de` and `fr` rather than `es-ES`, `de-DE`, `fr-FR`. The two vocabularies differ, and the store's own mapping between them is exactly that — `pt-BR` and `zh-Hans` are qualified on both sides. The language-level code is also the more useful of the two: `es` covers the Spanish of every region, where `es-ES` would answer an `es-MX` user in English.

## Keeping the catalogs in step with the code

The `Localizable` catalogs are neither written nor maintained by hand. During a build the extractor reads the sources (`SWIFT_EMIT_LOC_STRINGS` is on) and emits a `.stringsdata` file per source file; `xcstringstool sync` merges those into the catalog.

**Build every platform before syncing, and give each target only its own files.** Both halves fail silently:

```bash
xcodebuild build -project Vaultic.xcodeproj -scheme Vaultic \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' \
  -derivedDataPath /tmp/autheris-dd CODE_SIGNING_ALLOWED=NO
xcodebuild build -project Vaultic.xcodeproj -scheme Vaultic \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/autheris-dd CODE_SIGNING_ALLOWED=NO
xcodebuild build -project Vaultic.xcodeproj -scheme VaulticWatch \
  -destination 'generic/platform=watchOS' \
  -derivedDataPath /tmp/autheris-dd CODE_SIGNING_ALLOWED=NO

# the app's own catalog: what the Vaultic target extracted, and nothing else
xcrun xcstringstool sync Vaultic/Localizable.xcstrings \
  --stringsdata $(find /tmp/autheris-dd -name '*.stringsdata' \
    -path '*Vaultic.build*' -not -path '*VaulticWatch.build*') \
  --skip-marking-strings-stale

# the watch's, from the watch target's own build
xcrun xcstringstool sync VaulticWatch/Localizable.xcstrings \
  --stringsdata $(find /tmp/autheris-dd -name '*.stringsdata' -path '*VaulticWatch.build*') \
  --skip-marking-strings-stale
```

One platform's build only extracts the branches that platform compiles. Inside `#if os(macOS)` sit the entire Mac preferences window, the camera-permission copy, and five Settings rows — an iOS-only extraction leaves every one of them out, and they ship in English while the catalog looks complete. (That is not hypothetical: it is how this section came to be written.)

The `-not -path '*VaulticWatch.build*'` guards the same mistake in another hat, and it is the one that produced the watch's catalog. An iOS build of the `Vaultic` scheme **builds the watch app and embeds it**, so the watch's `.stringsdata` lands under `Vaultic.build` too, and a plain `find '*Vaultic.build*'` sweeps its five strings into the *phone's* catalog, where no phone view will ever ask for them.

`--skip-marking-strings-stale` is what makes "syncing does not disturb what is already there" true. The app's catalog holds an entry no Swift source yields — `Autheris`, the product name, marked `shouldTranslate: false` so Xcode stops offering it — and a sync without the flag marks that stale and deletes it, which `testTheProductNameIsNotTranslated` fails on. With the flag, syncing is additive and idempotent: run it twice and the file is byte-identical.

**`xcstringstool sync` is never pointed at the `InfoPlist` catalogs, and should not be.** Their keys *are* `Info.plist` keys — `NSCameraUsageDescription` and friends — which no Swift file says and no `.stringsdata` mentions, so there is nothing for a sync to merge. Xcode keeps that file in step with the `Info.plist`; what is written by hand there is only the translations. Pointing sync at it adds nothing, and without the flag it strips the keys.

## A `String` property is a localization bug

The trap this app hit most, and the one that leaves no trace: `Text("Cancel")` takes a `LocalizedStringKey` and is looked up, while `Text(someString)` renders what it is given. So a view declaring `let title: String` and showing it with `Text(title)` opts every literal at every call site out of localization — and the extractor agrees with it, so nothing appears in the catalog and nothing looks wrong.

The same shape appeared five more ways, all now fixed:

| Shape | Where it was |
| --- | --- |
| `String` property shown by `Text` | `OnboardingFeature.title`/`.description`, `QRCodeView.title`, `SecretKeySection.title`, `AccentTheme.displayName` |
| `String` parameter shown by `Text`/`Label` | `SettingsView.actionRowLabel(_:systemImage:)`, `WelcomeView.highlight(_:)`, `ImportConfirmationView.statRow(label:value:)` |
| `String` parameter built from a literal tuple | the alert results in `AutherisApp`, `AddTokenView`, `SettingsView`, `RecentlyDeletedView` |
| `String` state assigned a literal | every `alertMessage`, `restoreErrorMessage`, `generationError`, `supportErrorMessage`, `failureView(message:)` — now `String(localized:)` |
| Ternary of two literals | `Text(cond ? "Next" : "Get Started")` and friends, which infer as `String`; each is now a typed `LocalizedStringKey` property |

Direct UIKit and AppKit text assignments are the same problem in another dress: `label.text = "…"` and `alertAction.title = "…"` take a `String`, so the scanner's overlay and its permission prompts use `String(localized:)` too.

## Plurals

`"\(count) token\(count == 1 ? "" : "s")"` is correct in exactly one language, and it is the one you are reading this in. Those nine strings are now catalog entries with plural `variations`, so the rule comes from the language rather than from the code: `%lld Code` / `%lld Codes` in German, `Supprimer %lld code` / `Supprimer %lld codes` in French, and a single form for Japanese and Simplified Chinese, which have no `one` category at all. English keeps the behaviour it had, count-of-one awkwardness included.

## What is deliberately not localized

- **The in-app changelog history** (`ChangelogRelease.changes`, back to 1.0). The chrome around it is translated; the release notes themselves are long-form prose mirroring the App Store copy for versions that have already shipped.
- **The support-email draft** (`SupportMailData.troubleshootingTemplate`). Support answers in English, and a half-translated bug report is worse than a clear English one. The error shown when Mail cannot be opened *is* translated.
- **`debugInfo`** in `ImportConfirmationView`, which is assigned only inside `#if DEBUG`.
- **The product name**, which carries `"shouldTranslate": false` so Xcode stops offering it — in `Vaultic/Localizable.xcstrings`, and as `CFBundleName` and `CFBundleDisplayName` in both `InfoPlist` catalogs.

## The test

`VaulticTests/LocalizationCoverageTests.swift` guards the shape of all four catalogs, since it cannot judge the wording: every entry has all six languages, none is left at `new`, an entry marked `shouldTranslate: false` carries no translations to contradict that, every plural entry declares the categories its language actually has, and every translation keeps exactly the placeholders its key has — that last one caught a singular form that had dropped its `%lld`, which would have hidden the count.

Two of its tests reach outside the app. One reads the sources — both targets, each against its own catalog — so a literal the extractor never saw is a failure here rather than English in the shipped app; it checks what it can be certain of, one-line literals with no interpolation, because guessing at interpolations would produce a test that cries wolf, and that same fence leaves the watch's five strings out of reach since they arrive through ternaries. The other reads the built `Autheris.app` and compares its compiled strings against the catalogs — `Localizable` for the app and the watch, `InfoPlist` for the prompts, each under the table the system actually reads — because a catalog full of translations proves nothing if the build never puts them in the bundle. The watch's copy is checked only by a run whose host build embedded it, which the iOS run does and the Mac run does not.

# Development material inside the app target

`Vaultic/` is one `PBXFileSystemSynchronizedRootGroup`, and a synchronized folder copies **every** non-Swift file it contains into the bundle as a resource. That is not a theoretical hazard: the folder used to hold a Teenybase/Cloudflare Workers scaffold at `Vaultic/backend/`, and its `.dev.vars` — real JWT signing secrets, an admin service token, a Mailgun API key — was being copied straight into `Autheris.app`, readable by anyone who downloaded the app. It sat there unnoticed across several releases.

That scaffold has been **deleted**. Nothing used it: the app is a local-only authenticator that talks to no backend, the project's own IDE registrations pointing at it were dangling symlinks, its `node_modules` were never installed, `wrangler.toml` still carried the starter template's placeholder account and database ids, and no dev server ever ran. It has gone along with the credentials it held — nothing is left to rotate or revoke.

Some files in `Vaultic/` are not app content — local tooling configuration, and the project's own `Info.plist` — so they are excluded from the target's membership by name:

```
membershipExceptions = (
    .mcp.json,
    CLAUDE.md,
    Info.plist,
);
```

Three things are worth knowing before editing that list:

- **A synchronized folder can only be told to leave files out one at a time.** Listing a directory does *not* exclude its contents: both `backend` and `backend/` were tried, and both left `backend/.dev.vars` in the bundle. Resources are also **flattened** as they are copied, so a source path of `Vaultic/backend/package.json` arrives at the bundle root as `package.json`.
- **Xcode rewrites the list.** It reorders entries, drops any that no longer correspond to a real member, and removes quotes it does not need. That is normal, and useful — deleting `Vaultic/backend/` pruned its entries automatically — but it also means a hand-edit can be silently normalised away, so re-read the file after saving the project in Xcode.
- **A blacklist that nothing checks is a blacklist that rots**, which this one demonstrably did. `VaulticTests/BundledResourcesTests.swift` now fails if developer material reaches the bundle again, matching both by name and by *shape* (extensions such as `.md`, `.toml`, `.ts`, and hidden files), so a renamed or newly-added file is caught too. It walks the whole bundle, so the embedded watch app is covered as well, and it asserts the app's real content is still copied so it cannot pass on an empty bundle.

**One consequence is not fixable from here.** The `.dev.vars` values were committed from `169e539` onward, and deleting a file does not delete its history. The credentials belonged to a scaffold that was never deployed, so the practical exposure is small — but if any of those values were ever reused elsewhere, they should be treated as published and rotated at their source.
