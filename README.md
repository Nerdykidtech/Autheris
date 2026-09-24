# Autheris

<p align="center">
  <img src="https://eddington.tech/autheris/og-image.png" alt="Autheris - Secure 2FA Token Manager for iOS and macOS" width="600">
</p>

<p align="center">
  <a href="https://apps.apple.com/app/autheris">
    <img src="https://img.shields.io/badge/Download_on_the_App_Store-0D96F6?style=for-the-badge&logo=apple&logoColor=white" alt="Download on the App Store">
  </a>
  <img src="https://img.shields.io/badge/Platform-iOS%20%7C%20iPadOS%20%7C%20macOS%2026.0%2B-000000?style=for-the-badge&logo=apple" alt="iOS, iPadOS and macOS 26.0+">
  <img src="https://img.shields.io/badge/SwiftUI-FA7343?style=for-the-badge&logo=swift&logoColor=white" alt="SwiftUI">
</p>

**Autheris** is a secure, privacy-focused two-factor authentication (2FA) token manager for iPhone, iPad, and Mac. Built with SwiftUI and designed with zero-knowledge architecture — your tokens never leave your device unless you explicitly choose to export them or turn on iCloud Sync.

## Features

- 🔐 **Privacy-First Design**: Blur app content when backgrounded, hide codes in app switcher, and cover them while the screen is being recorded or mirrored
- 👁️ **Setup Key Access**: View, copy, or edit a token's secret — masked by default, tap to reveal
- ☁️ **Optional iCloud Sync**: Off by default. When enabled, tokens sync across your own devices through your private iCloud database, with secret keys end-to-end encrypted
- 📱 **Native Everywhere**: One SwiftUI codebase for iPhone, iPad, and Mac — no Catalyst, no "Designed for iPad"
- 📸 **QR Code Scanning**: Quick token setup from any 2FA QR code
- 📤 **Export & Backup**: Local backup files and QR exports you control (stored in the app sandbox, protected by the device passcode, not additionally encrypted)
- 📥 **Easy Migration**: Import from Google Authenticator
- 🗑️ **Recently Deleted**: A deleted code stays recoverable on your device for 7 days before it is removed for good
- 📌 **Pin and Reorder**: Pin the codes you use most to the top, and drag the rest into whatever order suits you
- 🔍 **Quick Search**: Find tokens instantly
- 🎨 **Clean Interface**: Simple, distraction-free design

## Tech Stack

- **Language**: Swift 5.9+
- **Framework**: SwiftUI
- **Architecture**: MVVM with Combine
- **Storage**: JSON in the Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`) — the data protection keychain on macOS, via `kSecUseDataProtectionKeychain`. See [Security](#security) for what this does and does not protect
- **Sync**: CloudKit private database (optional, opt-in per device)
- **Backend**: Cloudflare Workers (optional, used for issuer logo lookups only)

## Security

Autheris is designed with security in mind:

- No account required — fully offline by default
- No analytics or tracking
- No cloud storage unless explicitly enabled in Settings
- Open source for transparency

### Where tokens actually live

Tokens (including their TOTP secrets) are persisted locally as JSON in the iOS **Keychain** with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. The Keychain protects the data from other apps, keeps it device-only (it does not migrate with iCloud Keychain or an encrypted backup), and only exposes it while the device is unlocked. A full compromise of the device — including a forensic extraction — should still be treated as a compromise of the tokens. Backups written by the in-app Backup screen go to the app's Documents directory; unlike the Keychain, those files are plain JSON and inherit only the app-sandbox/device-passcode protection.

A first launch after upgrading migrates any legacy `UserDefaults` copy into the Keychain and deletes the plaintext copy.

Deletion tombstones are stored in the Keychain too, under their own account. They used to live in `UserDefaults`, which was the wrong home for them: `UserDefaults` is wiped when the app is deleted while the Keychain is not, so a reinstall lost the tombstones that suppress deleted tokens *while the tokens themselves came back* — and the next sync would re-import from iCloud everything the user had deleted. That is exactly the guarantee tombstones exist to provide, so losing them is not a cosmetic bug. The legacy tombstone copy is migrated on the same first launch, and only removed once the Keychain write has succeeded.

### What the privacy screen covers

The rule lives in `Vaultic/PrivacyShield.swift`, which is pure so it can be unit tested. Content is shielded when either of two things is true:

- **The app is not frontmost** — the app switcher and the home screen. Controlled by *Hide codes in app switcher* (a full cover) and *Blur when backgrounded* (a softer treatment).
- **The screen is being recorded or mirrored**, while the app is still frontmost. This is the case that produces no `scenePhase` change and no "will resign active", so there is nothing for the existing app-lifecycle notifications to hang off. It is observed through `UIScreen.capturedDidChangeNotification` in `Vaultic/ScreenCaptureMonitor.swift` and controlled by *Hide codes while recording or mirroring*.

The two reasons are OR-ed rather than exclusive: a device can be recording while the app sits in the background, and honouring only the app-switcher setting there would leave the recording with a visible — merely blurred — token list. All three toggles default to on.

One thing this cannot cover: **a screenshot**. iOS posts no notification for one, because it is a single frame taken without the app's involvement, so the capture protection does not apply to it and the app does not claim otherwise.

### Recently Deleted

Deleting a code moves a copy into **Recently Deleted** (**Settings → Data → Recently Deleted**), where it stays recoverable for **7 days** and is then removed for good. The window and the restore rules live in `Vaultic/TrashBin.swift`, which is pure so both can be unit tested.

The trash is deliberately **local to the device and never synced**. A delete still writes a tombstone immediately, so the code disappears from the user's other devices straight away — the trash does not delay or soften that. Restoring puts the code back stamped with a fresh `modifiedAt`, which is what makes the restore a *newer write* than the tombstone it is undoing; without that, the next sync would delete it again.

It is stored in the Keychain under its own account, with the same protection as live codes. The trade-off is explicit: a deleted code's secret stays on the device for those 7 days instead of being gone the moment you tap delete. Use **Delete Now** (swipe a row) or **Delete All** to remove it immediately.

Known gap: `restoreFromBackup` replaces the token list wholesale and does **not** route the replaced codes through the trash, so restoring a backup is still irreversible.

### What iCloud Sync sends, and how

Sync is opt-in and only ever uses the **private** CloudKit database, which is scoped to the signed-in iCloud account and is not readable by the developer.

- `label`, `account`, `secret`, `timerRingHex` and `isPinned` are written exclusively through `CKRecord.encryptedValues`, so CloudKit encrypts them end to end with keys it manages on the user's behalf. They never appear as readable fields and are not visible in the CloudKit dashboard. (`isPinned` is not a secret, but it is still a statement about which accounts matter to this user, so it is encrypted alongside the label rather than left readable on Apple's servers.)
- Only `modifiedAt`, `deleted`, `fingerprint`, `algorithm`, `digits` and `period` are plain fields. None of them reveal a secret: `fingerprint` is a SHA-256 over the record content (including the token id, so identical secrets on two records never collide) and is a one-way hash of a high-entropy base32 secret.
- Deleting a token replaces its record with a **tombstone** whose encrypted fields are explicitly cleared, so the secret does not linger in iCloud after a delete.

## iCloud Sync

Sync is a per-device setting in **Settings → iCloud Sync**. When it is off, CloudKit is never contacted. When it is on:

- **Add / edit** a token on one device and it appears on the others; the newest edit wins (`OTPCode.modifiedAt`), with a deterministic tie-break if two devices edited at the same instant.
- **Delete** a token anywhere and it is removed everywhere. Deletes are tombstones rather than record removals, so a delete always beats an older edit from a device that was offline, and the tombstones themselves are kept in the Keychain so they survive an app reinstall. The one exception: a device that stayed offline longer than the 30-day tombstone retention and still holds a live copy can reintroduce the token — the deliberate trade-off for not carrying deletion bookkeeping on every device forever.
- **Status** is shown in Settings: `Synced` (with a relative "last updated"), `Syncing…`, `Sync Paused` when offline, `Sign in to iCloud`, or `Sync unavailable` when the build or container is not configured.
- **Failures never block the app.** Local tokens are always authoritative for the device on screen; a failed sync is retried on the next edit, on foreground, or on a silent push.
- **Turning sync off** asks what to do: keep the tokens on this device (default) or delete the iCloud copy first, which also removes them from the other devices. That deletion sweeps every record type the app has ever written, including the [legacy one](#the-legacy-autherissyncrecord-type).
- **Pinning syncs; the manual order does not.** A pin is a property of the code (`OTPCode.isPinned`) and travels like any other edit. The order you drag codes into is per-device, like arranging app icons — the rules live in `Vaultic/TokenOrdering.swift`. Syncing the order would mean a `sortIndex` field, and a single drag would then rewrite many records at once, bumping each `modifiedAt` and letting a concurrent edit on another device silently drop the reorder.

Remote changes arrive via a `CKDatabaseSubscription` silent push (`AppDelegate` → `SyncRemoteNotificationRouter` → `OTPDataStore`), with a foreground sync as the fallback for anything missed.

### Required project configuration

The target already declares these; they are listed so a new machine or a fresh Apple Developer account can reproduce them.

| Setting | Value |
| --- | --- |
| iCloud container | `iCloud.com.eddingtontech.autheris` (must match `CloudKitTokenSyncService.containerIdentifier`) |
| Entitlements file | `Vaultic/Vaultic.entitlements` (wired up via `CODE_SIGN_ENTITLEMENTS`) |
| Capabilities | iCloud → CloudKit, Push Notifications, Background Modes → Remote notifications |
| `UIBackgroundModes` | `remote-notification` (in `Vaultic/Info.plist`) |
| `aps-environment` | `$(APS_ENVIRONMENT)` — `development` for Debug, `production` for Release |

The container identifier in `Vaultic.entitlements` is tied to the `com.eddingtontech.autheris` bundle id and the `37GWLWW278` team. Forking this project means creating your own container and updating both the entitlements file and `CloudKitTokenSyncService.containerIdentifier`.

### Deploying the CloudKit schema

Records use the record type **`AutherisToken`** in the private database. In development, CloudKit creates the schema implicitly on the first successful save — no manual setup is needed to run from Xcode. Before shipping, or if `/usr/bin/log` shows `did not find record type: AutherisToken`:

1. Open the CloudKit Console for the container.
2. Confirm `AutherisToken` exists with fields `modifiedAt` (Date), `deleted` (Int64), `fingerprint` (String), `algorithm` (String), `digits` (Int64), `period` (Int64), plus the encrypted fields `label`, `account`, `secret`, `timerRingHex`, `isPinned`. In the app these names live in exactly one place — the nested `CloudKitTokenSyncService.Field` enum, whose `plain` / `encrypted` / `all` lists are the authoritative form of this table. Compare the Console against *that*, not against a copy of this README: a CloudKit field name is a string, so a typo silently creates a new field instead of failing to compile, and a field that should be encrypted but is written plainly ends up readable on Apple's servers.

**Every encrypted field holds a String.** `label`, `account`, `secret`, `timerRingHex` and `isPinned` are all String-typed in the Console — including `isPinned`, which stores `"1"` / `"0"` (see `EncryptedBool`). Give the new field the same type the Console already shows for `timerRingHex` rather than a numeric one for the boolean: that is the only encrypted shape exercised against the production container, and CloudKit fixes a field's type once it exists, so a wrong choice can only be undone by picking a different field name.
3. **Add a Queryable index on `recordName`** — see below. This is not optional and is the step most likely to be missed.
4. Deploy the schema from the development environment to production.

A first sync against a container that has never stored a record is expected to find no record type; `CloudKitTokenSyncService` treats that as "no records" rather than an error, so the very first sync still bootstraps.

#### Upgrading a container that already holds records

Adding `isPinned` changes the `AutherisToken` schema, so an existing container needs the new encrypted field deployed (step 2 above covers what to check). Three consequences worth expecting, none of which needs code changes:

- **The field is absent from existing records, which reads as `false`.** `CloudKitTokenSyncService.decode` treats a missing `isPinned` as unpinned, and `OTPCode`'s hand-written decoder does the same for a local token persisted before pinning existed. Nothing has to be back-filled.
- **The value is a String (`"1"` / `"0"`), not a number.** `EncryptedBool` owns both directions and reads leniently, so an integer-typed field left over from a development experiment still reads correctly rather than reporting every pin as `false`.
- **`SyncFingerprint`'s canonical version moved from `v1` to `v2`**, because a fingerprint has to see every field the user can change — otherwise toggling a pin would look like "no change" and never sync. Every token's fingerprint therefore differs from the `v1` value its iCloud record still carries, so the first sync after upgrading re-exchanges each record once and settles. That is expected and one-time.

If `isPinned` already exists in your development container with the wrong type, delete the field and let the next save recreate it — CloudKit will not change a field's type in place.

#### The `recordName` index is required

Sync reads the private database with an unfiltered `CKQuery` (`NSPredicate(value: true)`). CloudKit refuses that unless the system `recordName` field carries a **Queryable** index, failing with `Field 'recordName' is not marked queryable`.

**CloudKit creates no indexes on a record type that was created implicitly by saving**, so the sequence is: the first sync writes records successfully (creating `AutherisToken`), and the *next* query fails. Nothing in the app can work around this — it is a schema property. In the Console:

1. **Schema → Indexes**, and select the record type.
2. **Add Basic Index** → select the metadata entry (`__recordID`, which displays as `recordName`).
3. Set **Index Type = Queryable** → **Save Changes**.
4. Repeat for **every** record type the app queries — `AutherisToken` and, if present, the legacy `AutherisSyncRecord` (the delete sweep queries it).
5. **Deploy to production.** Development indexes do not carry over on their own, and there are reports of these metadata index changes being omitted from a deploy diff — so verify in a TestFlight build before release, not just in the Console.

Until the index exists, the Settings row reports "Sync unavailable" with this reason rather than a generic failure.

### The legacy `AutherisSyncRecord` type

A sync implementation was built on a branch, later reverted, and never shipped. Because CloudKit keeps the development schema once a record type has been written, a container used during that work still contains a second type, **`AutherisSyncRecord`**, with a different field set (`kind`, `updatedAt`, `contentHash`, `settingKey`, `value`, and a *plain* `timerRingHex`).

The current app never reads or migrates it — the merge engine only ever sees `AutherisToken`, so the two types cannot interfere. It matters for one reason: those rows can hold real (encrypted) token secrets from the abandoned build, so **Settings → iCloud Sync → Delete Tokens from iCloud sweeps both types**, otherwise a user's request to remove their iCloud copy would leave a copy behind that nothing in the app can reach. If you see that type in the Console, that is expected; do not deploy it to production.

## Tests

`VaulticTests` (XCTest) covers the logic that is easy to get wrong and cheap to assert: the iCloud conflict-resolution rules, the tombstone and Recently-Deleted bookkeeping, pinned-first ordering and drag-to-reorder, `OTPCode`'s backward-compatible decoding, the mirrored preferences, the privacy-shield rules, and `BackupCrypto`. Each of those rule sets lives in a pure, dependency-free type — `SyncMergeEngine`, `SyncTombstoneStore`, `TrashBin`, `TokenOrdering`, `AppPreferences`, `PrivacyShield` — precisely so it can be asserted without a simulator.

```bash
xcodebuild test -project Vaultic.xcodeproj -scheme Vaultic \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
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

## macOS

Autheris is one Xcode target (`Vaultic`) that builds for iPhone, iPad, and Mac — `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"`. The Mac app is a real AppKit/SwiftUI app, not Mac Catalyst and not "Designed for iPad", so it gets native window and menu-bar behaviour and the roomy token grid the iPad uses. Mac-only build settings are scoped with `[sdk=macosx*]`, and the Mac has its own entitlements file (`Vaultic/Vaultic-macOS.entitlements`), so the iOS build is untouched.

The target is still called `Vaultic`, but its **product** is `Autheris`: `PRODUCT_NAME = Autheris` with `PRODUCT_MODULE_NAME = Vaultic`, so the app ships as `Autheris.app` while the Swift module the tests import stays `Vaultic`. This matters on the Mac specifically — iOS names the home-screen icon from `CFBundleDisplayName`, but macOS takes the app's name from the bundle and `CFBundleName`, so `PRODUCT_NAME = "$(TARGET_NAME)"` is what once shipped a Mac app called `Vaultic.app` with a "Quit Vaultic" menu item. Keep `PRODUCT_MODULE_NAME` in sync with the `@testable import Vaultic` in `VaulticTests`, and `TEST_HOST` pointing at `Autheris.app/.../Autheris`.

Most of the source is shared. The platform differences are named once, in `Vaultic/Platform/`, rather than branched at every call site:

| File | What it covers |
| --- | --- |
| `PlatformImage.swift` | `PlatformImage`/`PlatformColor` (`UIImage`/`NSImage`, `UIColor`/`NSColor`), `Image(platformImage:)`, PNG encoding and `CGImage` bridging |
| `PlatformSemanticColors.swift` | AppKit spellings for `NSColor.systemBackground`, `.separator`, `.secondarySystemBackground`, `.secondarySystemGroupedBackground` |
| `PlatformNavigation.swift` | Navigation titles, sheet sizing (macOS has no `presentationDetents`), `fullScreenCover`, search placement, list style, toolbar placements, AutoFill and keyboard hints || `PlatformFeedback.swift` | `Haptics` — a no-op on macOS, which has no haptic engine |
| `PlatformShareSheet.swift` | `UIActivityViewController` on iOS, `NSSharingServicePicker` on the Mac |
| `PlatformLifecycle.swift` | App-activation notification names, mapping iOS background/foreground onto macOS hide/unhide |
| `PlatformApplication.swift` | Machine model and OS version for the support template, the camera privacy deep-link, in-app-mail availability |
| `WindowCaptureExclusion.swift` | Excludes the window from capture on macOS; a no-op on iOS, which can detect capture instead |

Three behaviour differences are worth knowing about, because they are deliberate rather than oversights:

- **Screen-capture protection works differently, and is stronger on the Mac.** iOS *detects* recording (`UIScreen.isCaptured`) and reacts; macOS offers no such signal, because ScreenCaptureKit tells the capturer and not the captee. So the Mac does not try to detect anything — it excludes its windows from capture outright via `NSWindow.sharingType = .none` while "Hide codes when screen captured" is on. The trade-off, stated plainly: that also keeps the Mac app out of *your own* screenshots and screen recordings. Turning the setting off lifts the exclusion and leaves you alone.
- **Camera permission needs a relaunch.** macOS applies a newly granted camera permission on the next launch, not the current one, so after you grant it the scanner tells you to quit and reopen rather than sitting on a spinner.
- **There are no haptics.** The copy, reveal, and save confirmations are silent on a Mac by design.
- **Settings is a preferences window, not a sheet.** On iPhone and iPad it is the sheet it has always been. On the Mac it is a `Settings` scene — so it gets the standard "Settings…" menu item and ⌘, — and the same settings are laid out across General, Privacy, iCloud, Data and Help tabs instead of one long list. Both containers are drawn from the same section views, so a setting is added in exactly one place.

Two things every Mac sheet has to do for itself — both of which fail *silently* if forgotten, so they are worth checking whenever a sheet is added:

- **Declare a size with `platformSheetSize()`.** A macOS sheet has no size of its own. Content with nowhere to lay out does not get clipped or scrolled — it simply does not appear, and the sheet opens as an empty box showing only its toolbar.
- **Use `platformSheetLeading` / `platformSheetTrailing` for its buttons**, not `platformLeading` / `platformTrailing`. The latter are *window*-toolbar placements, and a sheet is not the window, so those buttons are dropped entirely and the sheet cannot be closed — macOS sheets do not dismiss on outside-click either.

### Submitting the Mac app

macOS is a **separate App Store Connect platform** (`MAC_OS`), not a device family like iPad. An iOS app record serves iPhone and iPad from one version; macOS needs its own version, its own screenshots, and a different build artifact. The Mac minimum is macOS 14.0 (`MACOSX_DEPLOYMENT_TARGET`) — that floor is forced by `openSettings`, which is macOS 14+; 13.0 is two errors away if it is ever worth a fallback.

Already done for 2.2, and repeatable per release:

```bash
# Add the macOS version. 2.2's is b9845c12-38c5-447c-973b-eab852a6cce2.
asc versions create --app 6760686327 --version 2.2 --platform MAC_OS \
  --copyright "© 2026 Hunter Eddington" --release-type AFTER_APPROVAL

# Push metadata/version/2.2/en-US.strings to it (needs the version ID from above).
asc localizations upload --version "<macOS version id>" \
  --path "metadata/version/2.2/en-US.strings"
```

Two things that catch people out:

- **A first Mac release has no What's New.** `asc` reports *"whatsNew cannot be set for this version (initial releases have no What's New section)"* and retries without it. Expected — set it from the next Mac release onward. The same file still carries `whatsNew` for the iOS version, where 2.2 is an update.
- **Universal purchase is automatic** because the Mac and iOS versions share one app record and bundle ID, so existing iPhone/iPad buyers get the Mac app at no extra cost. Nothing to configure.

The two steps still to do, neither of which `asc` can finish on its own:

1. **Mac screenshots.** Apple accepts 16:10 Mac images at 1280×800, 1440×900, 2560×1600 or 2880×1800. `asc screenshots sizes` lists only `APP_IPHONE_65` and `APP_IPAD_PRO_3GEN_129` — there is **no Mac display type**, so `asc screenshots upload` cannot place them; use the App Store Connect web UI or Transporter.

   A ready set is committed at `./screenshots/mac/` (2880×1800, the largest accepted size):

   | File | Screen |
   | --- | --- |
   | `autheris-mac-01-codes.png` | Token list with demo accounts |
   | `autheris-mac-02-settings.png` | Settings › General |
   | `autheris-mac-03-add-token.png` | Add Token › Scan QR Code |

   These were **rendered from the app's own views** — `OTPCardView`, `SettingsView(presentation: .preferences)` and `AddTokenView` — with throwaway demo tokens, then composed onto a headline frame. The vault is never captured, so nothing private can leak into a public image. Two details worth knowing if you regenerate them:

   - **The countdown bar is wall-clock driven.** A render taken in the last second of a period shows a red, almost-empty bar — an alarming state that says nothing about the app. Wait for a mid-period phase before rendering.
   - **`TabView` and `ProgressView` cannot rasterise offscreen.** `ImageRenderer` draws SwiftUI's unsupported-view glyph instead; render through `NSHostingView` + `cacheDisplay`, and draw the Settings toolbar yourself, because the offscreen `TabView` comes out as a clipped fragment.

   To capture a real window instead, note it grabs the window at its own size, so it still needs compositing onto an accepted size:

   ```bash
   # The app must already be running, and the window you want must already be showing.
   asc screenshots capture --bundle-id com.eddingtontech.autheris \
     --name "home" --provider macos --output-dir ./screenshots/mac
   ```

   Either way, use throwaway entries — these images are public, and the token list shows whatever is in the vault.

   **Order is upload order, not filename order.** App Store Connect keeps the order the files were added in, so upload them in the sequence you want customers to see — the first image is the one that appears in search results and the product page. `asc screenshots download` sorts by *filename* when numbering what it writes, so it does not tell you the real order; use `asc screenshots list`, which returns them in display order.

   **Screenshots lock once the version is added for review.** In `READY_FOR_REVIEW`, `asc screenshots delete` fails with *"Can't Delete Screenshot while Ready For Review appScreenshots"*. Two things that do not get you out of it: `asc review items-update --state REMOVED` is rejected (`state` cannot be sent in an UPDATE), and `asc review submissions-cancel` is rejected (`Resource is not in cancellable state`). The web UI's "Remove from Review" is a **DELETE on `reviewSubmissionItems`**, which `asc` does not expose — so either use the UI, or call it directly and then restore the submission:

   ```bash
   # 1. remove the version from the draft (204 No Content on success)
   curl -X DELETE -H "Authorization: Bearer $JWT" \
     "https://api.appstoreconnect.apple.com/v1/reviewSubmissionItems/$ITEM_ID"

   # 2. reorder, then put the version back
   asc screenshots upload --version-localization "<loc id>" \
     --path ./screenshots/mac --device-type APP_DESKTOP --replace
   asc review submissions-create --app 6760686327 --platform MAC_OS
   asc review items-add --submission "<new submission id>" \
     --item-type appStoreVersions --item-id "<version id>"
   ```

   Mint `$JWT` with ES256 from the ASC API key (`kid`, `iss`, `aud: appstoreconnect-v1`, `exp` ≤ 20 min). Expect one empty leftover draft afterwards: an emptied submission can be neither cancelled nor deleted (`reviewSubmissions` allows only CREATE, GET and UPDATE), and ASC leaves it behind.


2. **The build, as a signed `.pkg` — not an `.ipa`.** The `app_store_build` flow documented elsewhere produces an IPA, which is iOS only. For the Mac App Store, one prerequisite: a Mac App Store upload needs an **Apple Distribution** certificate (signs the app) and a **Mac Installer Distribution** certificate (signs the package). A development certificate will not do:

   ```bash
   asc certificates csr generate --common-name "Autheris Mac Distribution" \
     --key-out ~/.asc/mac-signing/distribution.key \
     --csr-out ~/.asc/mac-signing/distribution.csr
   asc certificates create --certificate-type DISTRIBUTION \
     --csr ~/.asc/mac-signing/distribution.csr

   asc certificates csr generate --common-name "Autheris Mac Installer" \
     --key-out ~/.asc/mac-signing/installer.key \
     --csr-out ~/.asc/mac-signing/installer.csr
   asc certificates create --certificate-type MAC_INSTALLER_DISTRIBUTION \
     --csr ~/.asc/mac-signing/installer.csr
   ```

   Import each returned certificate into the login keychain alongside its key, then archive and export. Note `-legacy`: OpenSSL 3 defaults to a PKCS#12 encoding that macOS `security` rejects with *"MAC verification failed during PKCS12 import (wrong password?)"* — the password is correct, the format is not.

   ```bash
   openssl pkcs12 -export -legacy -inkey distribution.key -in distribution.cer \
     -out distribution.p12 -passout pass:temp
   security import distribution.p12 -P temp \
     -T /usr/bin/codesign -T /usr/bin/productbuild -T /usr/bin/security

   xcodebuild archive -project Vaultic.xcodeproj -scheme Vaultic \
     -destination 'generic/platform=macOS' -configuration Release \
     -archivePath build/Autheris.xcarchive -allowProvisioningUpdates

   xcodebuild -exportArchive -archivePath build/Autheris.xcarchive \
     -exportPath build/export -exportOptionsPlist ExportOptions.plist \
     -allowProvisioningUpdates        # method: app-store-connect
   ```

   `-allowProvisioningUpdates` is what creates the Mac App Store provisioning profile — it needs the distribution certificate in the keychain first, which is why the certificate step comes before the archive. The archive itself signs with the *development* identity; the export is what re-signs with distribution.

   Then upload and attach:

   ```bash
   asc builds upload --app 6760686327 --pkg build/export/Autheris.pkg \
     --version 2.2 --build-number 1
   asc builds wait --app 6760686327 --newest     # processing takes a minute or two
   asc versions attach-build --version-id "<macOS version id>" --build "<build id>"
   ```

   Verify with `asc versions view --version-id "<id>" --include-build`, which reports `buildId`. **`asc versions list` does not inline the build relationship and will report no build even when one is attached** — do not trust it for this.

   To confirm a `.pkg` before uploading, without installing it: `pkgutil --check-signature X.pkg` should name *3rd Party Mac Developer Installer*, and `pkgutil --expand-full X.pkg /tmp/x` then `codesign -dv` on the app inside should name *Apple Distribution*.


## Installation

```bash
git clone https://github.com/nerdykidtech/Autheris.git
cd Autheris
open Vaultic.xcodeproj
```

Requires the iOS 26 and macOS 26 SDKs (Xcode 26 or later). The Mac app also needs a Mac provisioning profile for `com.eddingtontech.autheris` — signing in with an Apple ID and building once with `-allowProvisioningUpdates` (or just ⌘R in Xcode) creates it.

## Download

<a href="https://eddington.tech/autheris">
  <img src="https://eddington.tech/autheris/app-icon.png" width="120" alt="Autheris App">
</a>

**[Get it on eddington.tech/autheris](https://eddington.tech/autheris)**

## Privacy Policy

View our privacy policy at [eddington.tech/autheris](https://eddington.tech/autheris)

## License

MIT License — see [LICENSE](./LICENSE) for details.

## Author

Built by [Hunter Eddington](https://eddington.tech) — System Engineer & IAM Engineer specializing in identity and access management.

---

<p align="center">
  <sub>Open source 2FA for iOS. No accounts. No tracking. Your tokens, your device.</sub>
</p>
