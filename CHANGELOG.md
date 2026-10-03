# Changelog

All notable changes to **Autheris** are documented in this file. Newest first.

This file mirrors the in-app changelog in [`Vaultic/ChangelogView.swift`](Vaultic/ChangelogView.swift) and the App Store release notes.

A version number lives in four places, and a release is not finished until they agree:

1. **`MARKETING_VERSION`** in `Vaultic.xcodeproj/project.pbxproj` — six build settings (app, tests and watch, Debug and Release). This is what the app and the App Store report.
2. **The `catalog`** in [`Vaultic/ChangelogView.swift`](Vaultic/ChangelogView.swift) — the release notes shown inside the app.
3. **This file** — the same notes, and the copy the repository keeps.
4. **[`metadata/version/<version>/<locale>.json`](metadata)** — the App Store listing: description, keywords, what's new, and promotional text. One file per locale (name and subtitle live in `metadata/app-info/<locale>.json`), in the canonical layout the `asc` CLI reads and writes — `asc metadata pull` to refresh it, `asc metadata push` to publish it.

   These were `.strings` files until 2.4. They were converted because `asc metadata validate` refuses the old layout outright ("no metadata .json files found"), so nothing could read them; `plutil -convert json` did the conversion and the extracted lengths matched the live listing exactly.

`VaulticTests/ChangelogReleaseTests.swift` fails if (1) and (2) disagree, because bumping the version without adding its notes is the drift that is easiest to miss — the app cheerfully reports a release its own changelog has never heard of.

## [Unreleased]

### Security

- On the Mac, the Settings window now shows the lock screen while Autheris is locked. It used to open with ⌘, without asking for Touch ID or your password, which gave access to QR transfer (every secret), unencrypted backups and the App Lock toggle itself. The Settings window is also now kept out of screen capture when "Hide codes while recording or mirroring" is on, like the main window.
- On the Mac, App Lock now re-locks 30 seconds after you switch to another app, as the Privacy settings say. It used to start counting only when Autheris was hidden or minimised, so switching away and back left it unlocked however long you were gone.
- Backups you create in Backup & Restore now stay on this device. They used to be copied into iCloud Backup and Finder backups along with the rest of the app's documents, so an unencrypted backup put every secret into those backups in plain text. Backups made by earlier versions get the same protection the next time Autheris opens.

### Fixed

- With iCloud sync on, deleting a code on one device now removes it from your other devices too. The other devices used to put it straight back. A code you deleted, re-added or restored from Recently Deleted while a sync was running could also be undone when that sync finished; it now stays the way you left it.

## [2.8] — October 2026

- Links that add codes — `autheris://import`, `otpauth://` and `otpauth-migration://` — now always show what they would add and wait for you to tap Import. They used to add codes the moment they arrived, and while App Lock was on, so another app or a web page could quietly plant entries in your list. A link that arrives while Autheris is locked now waits until you unlock it. ([GHSA-75h3-q43q-9338](https://github.com/Nerdykidtech/Autheris/security/advisories/GHSA-75h3-q43q-9338))
- Thanks to [@NotAFlightRisk](https://github.com/NotAFlightRisk) for finding and responsibly reporting this.
- Your codes, iCloud sync and settings are exactly where you left them.

## [2.7] — October 2026

- This release changes how Autheris looks in the App Store, not how it works — the listing now carries a new set of screenshots for iPhone, iPad, Mac and Apple Watch.
- Nothing else changed: no new settings, no new permissions, and no new network requests.
- Your codes, iCloud sync and settings are exactly where you left them.

## [2.6] — September 2026

- Autheris can now generate counter-based codes as well as the time-based ones it has always used. Some services hand you a counter instead of a code that changes on a timer: that code stays the same until you ask for the next one, and its card shows which counter it is on, with a Next button beside it.
- Scanning one of those codes used to add it as a time-based one, so its codes were always rejected and nothing on screen explained why. It now adds the right kind of code.
- Importing got the same fix. Counter-based accounts in a Google Authenticator export used to be skipped without a word, and Aegis and andOTP backups now bring their counters across too.
- The Apple Watch shows counter-based codes as well, with the counter where the countdown would be. The watch stays read-only, so you advance the counter on your iPhone.
- Settings → Privacy has a new switch, Fetch service logos. It controls the one request Autheris can make over the network — looking a service's icon up by name at logo.dev, which tells that logo service which brands you have. With it off, nothing is looked up and every service falls back to its letter.
- Autheris now speaks Spanish, French, German, Japanese, Simplified Chinese and Brazilian Portuguese — the same six languages the App Store listing has been translated into — including the camera and Face ID permission prompts and the Apple Watch app. If your device is set to one of them, the app opens in it.
- Your codes, iCloud sync and settings are exactly where you left them.

## [2.5] — September 2026

- Autheris now speaks Spanish, French, German, Japanese, Simplified Chinese and Brazilian Portuguese — the same six languages the App Store listing has been translated into since 2.4. If your device is set to one of them, the app opens in it.
- The Apple Watch app speaks them too, so the codes on your wrist read in the same language as the ones in your pocket.
- The camera and Face ID permission prompts are translated as well. Those come from the system rather than the app, so they were the last English a translated app still showed.
- Your codes, iCloud sync and settings are exactly where you left them.

## [2.4] — September 2026

- Autheris now has an Apple Watch app. Your codes are on your wrist — one at a time, a swipe or a turn of the Digital Crown apart, each with its own countdown.
- The watch app is deliberately read-only: there is no copy, no editing and no settings on the watch. Adding, changing and deleting codes still happens on your iPhone, and the iPhone sends the list over. Installing the watch app is what turns that on — if you never install it, nothing is sent.
- Codes are generated on the watch itself, so they keep counting down with your iPhone out of reach or switched off. A code you add on your iPhone appears on the watch within seconds, and a code you delete disappears just as quickly.
- The watch is a viewer, not a second vault to keep in step. Its copy of your codes gets the same protection the iPhone's does, and it is never edited there.
- Your codes, iCloud sync and settings are exactly where you left them.

## [2.3] — September 2026

- Autheris can now ask for an App Store rating. Settings has a Rate Autheris row under Help for whenever you want to leave one, and the app will ask by itself once, after you change a setting — never on launch, and at most once per version.
- On the Mac, the app is now named Autheris everywhere — it previously installed as Vaultic, so the Dock, the menu bar and your Applications folder called it something else. They now match the name the app already uses in the App Store.
- Your codes, iCloud sync and settings are exactly where you left them.
- If an older copy named Vaultic is still in your Applications folder, you can move it to the Trash — Autheris is the app from here on.

## [2.2] — September 2026

- Autheris now runs on the Mac — a real Mac app rather than a phone app stretched across the desktop. Your codes, sync and settings are unchanged: add an account on your iPhone and it is there on your Mac.
- Settings on the Mac is a proper preferences window. Open it from the gear or with ⌘, and find everything grouped into General, Privacy, iCloud, Data and Help.
- Scan QR codes with your Mac's built-in or attached camera, including Google Authenticator transfer codes.
- App Lock works on the Mac: Touch ID where your Mac has it, and your login password where it does not.
- Codes are hidden from screen sharing and recording, so a call or a demo cannot put your codes on someone else's screen.
- The small things a Mac expects: switch controls use the system's own blue, the accent colours sit in a row rather than a scroller, lists reorder by dragging a row directly, search lives in the window toolbar, and copied codes are marked as concealed so they do not travel to your other devices through Universal Clipboard.
- Support on the Mac opens your own mail app with the troubleshooting details already filled in.
- Fixed a set of Mac teething problems: some sheets opened as an empty box, several could not be closed at all, Recently Deleted had no way back, and the buttons in Settings did not respond everywhere they looked like they should.
- Fixed a crash when starting the Mac's QR scanner.
- Fixed a startup crash in builds where iCloud is unavailable — the app now opens normally and explains that sync is unavailable, instead of refusing to start.

## [2.1] — September 2026

- Autheris now runs on iPad as well as iPhone. Your codes, sync, and settings are unchanged — the app is simply built for the larger screen too.
- The token list is a grid on iPad — two codes per row, with a larger code and countdown on each card — instead of a single column stretched across the screen.
- Tap Edit and drag a card by its grabber handle — the same control as on iPhone. The other codes move out of the way as you carry one past them, and it settles where you let go.
- Onboarding, the import summary, and Settings are sized for the larger screen rather than stretched across it.

## [2.0] — September 2026

- Redesigned home screen: cleaner token cards with larger issuer icons, glanceable countdowns, and native search.
- Reorganized navigation: Settings is a full-screen hub for Privacy, iCloud Sync, Appearance, Data, Help, and About.
- Add Token and Edit Token are rebuilt as native forms, with PhotosPicker for QR screenshots and standard alerts. Account is optional, and the code on the Edit screen updates live as you change its settings.
- SHA-256 and SHA-512 can now be selected when adding or editing a code, not just SHA-1 — some services (myGov, for example) require SHA-256 and would previously reject every code.
- App Lock with Face ID / Touch ID — locks on launch and after 30 seconds in the background, with passcode fallback.
- Codes are covered while the screen is being recorded or mirrored to another display, alongside the existing app-switcher and background protection.
- Tokens, preferences, and pending deletions now live in the Keychain, so your accounts and settings survive reinstalling the app — and a code you deleted cannot come back afterwards.
- Password-encrypted backups: AES-GCM files protected by your own password, alongside the existing plain backup option.
- Import from more authenticators: unencrypted Aegis, andOTP, and 2FAS backup files.
- Copied codes and setup keys automatically clear from the clipboard after 60 seconds.
- Pin the codes you use most to the top of the list, and drag the rest into whatever order suits you.
- A deleted code is kept in “Recently Deleted” for 7 days, so a wrong tap is recoverable — restore it, or remove it for good straight away.
- Optional accent tints keep the default Autheris look unless you pick a theme.
- Fresh onboarding that matches the new design, with Reduce Motion support.
- The app is now named Autheris on your home screen, matching the name it uses in the App Store.
- Fixed a crash a malformed setup link or backup file could trigger, by validating a code's digit count and refresh period rather than trusting them.
- Polish pass: dark-mode contrast fixes, Dynamic Type, and accessibility improvements.

## [1.3] — September 2026

- Optional iCloud Sync in Settings — off by default, and iCloud is never contacted until you turn it on. Tokens sync across your own devices through your private iCloud database.
- Your secrets stay protected: label, account, secret, and ring color are end-to-end encrypted by CloudKit and are never stored in a readable form.
- Adds, edits, and deletes sync automatically. The newest edit wins, and deletes use tombstones so a token deleted on one device can't reappear from another device that was offline.
- Settings shows live sync status — Synced with “last updated,” Syncing, paused when offline, or Sign in to iCloud — and turning sync off asks whether to keep tokens on this device or delete them from iCloud first.

## [1.2] — September 2026

- Long-press a token and choose “View Secret” to see its setup key. The key is masked by default — tap it (or use the eye icon) to reveal, with Copy to grab it quickly.
- Secret edits happen in the same sheet and require an explicit Save; changes are validated as a Base32 key first, and canceling with unsaved edits asks before discarding.
- The Edit sheet keeps its original scope — service name, account, and ring color — with the same unsaved-changes guard.

## [1.1] — March 2026

- QR export uses compact JSON (no extra whitespace) and QR error-correction level L so more accounts fit in a single code.
- If the encoded URL still exceeds what a QR code can hold, the app stops loading indefinitely and explains the limit, with guidance to use Backup for file-based transfer.
- Countdown ring color can be customized per token in Edit: use the system color picker, or “Use service default” to follow the automatic issuer color.
- Settings shows marketing version and build from the bundle. Release notes live here under Changelog in the main menu.

## [1.0] — Initial release

- First release of Autheris: TOTP codes, search, backup and restore, QR import, privacy blur and app-switcher hiding, and issuer-aware visuals.
