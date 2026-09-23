# Changelog

All notable changes to **Autheris** are documented in this file. Newest first.

This file mirrors the in-app changelog in [`Vaultic/ChangelogView.swift`](Vaultic/ChangelogView.swift) and the App Store release notes.

A version number lives in four places, and a release is not finished until they agree:

1. **`MARKETING_VERSION`** in `Vaultic.xcodeproj/project.pbxproj` — four build settings (app and tests, Debug and Release). This is what the app and the App Store report.
2. **The `catalog`** in [`Vaultic/ChangelogView.swift`](Vaultic/ChangelogView.swift) — the release notes shown inside the app.
3. **This file** — the same notes, and the copy the repository keeps.
4. **[`metadata/version/<version>/en-US.strings`](metadata)** — the App Store listing: description, keywords, what's new, and promotional text.

`VaulticTests/ChangelogReleaseTests.swift` fails if (1) and (2) disagree, because bumping the version without adding its notes is the drift that is easiest to miss — the app cheerfully reports a release its own changelog has never heard of.

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
