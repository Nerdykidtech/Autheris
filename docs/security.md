# Security

How each of the promises on the [front page](../README.md#security-at-a-glance) is enforced — and the two things it deliberately does not cover.

Autheris has no account, no analytics and no server of its own, stores nothing in the cloud unless iCloud Sync is turned on, and is open source so all of this can be checked.

## Issuer icons

Every service in the list shows a brand icon, and it is looked up by name at **`img.logo.dev`** with a publishable key in `Vaultic/Info.plist` (`Vaultic/IssuerBranding.swift` is the only place that talks to it). Two things are worth being precise about, because the surrounding copy says "nothing leaves your device":

- The lookup sends the **service's name** — "GitHub", say — and the request's IP address. It does not send the secret, the account, or anything that identifies the user to us, and no result is stored anywhere but the device's own cache (`Caches/IssuerLogos`).
- It is still a statement about *which services someone has accounts with*, and that belongs to the user rather than to the app. **Settings → Privacy → Fetch service logos** turns it off; with it off nothing is looked up, services whose icons are already cached keep showing them, and the rest fall back to a letter. It is **on by default**, which is what the app has always done.

The honest summary: the *codes* never leave the device, and the *list of services* does unless that switch is off. A future release could bundle a small icon set or proxy the lookup so neither does — both are deliberate follow-ups rather than accidents.

`Vaultic/PrivacyInfo.xcprivacy` is the privacy manifest: `NSPrivacyTracking` false, nothing collected, and the two required-reason APIs the app actually uses (`UserDefaults` for its own preferences, file timestamps to list backups). The watch app has no manifest because it touches neither. The App Store Connect privacy answers should be checked against the icon lookup — see the note above.

## Where tokens actually live

Tokens (including their TOTP secrets) are persisted locally as JSON in the iOS **Keychain** with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. The Keychain protects the data from other apps, keeps it device-only (it does not migrate with iCloud Keychain or an encrypted backup), and only exposes it while the device is unlocked. A full compromise of the device — including a forensic extraction — should still be treated as a compromise of the tokens. Backup files are covered in [Backups](#backups).

A first launch after upgrading migrates any legacy `UserDefaults` copy into the Keychain and deletes the plaintext copy.

Deletion tombstones are stored in the Keychain too, under their own account. They used to live in `UserDefaults`, which was the wrong home for them: `UserDefaults` is wiped when the app is deleted while the Keychain is not, so a reinstall lost the tombstones that suppress deleted tokens *while the tokens themselves came back* — and the next sync would re-import from iCloud everything the user had deleted. That is exactly the guarantee tombstones exist to provide, so losing them is not a cosmetic bug. The legacy tombstone copy is migrated on the same first launch, and only removed once the Keychain write has succeeded.

If the stored codes are present but can't be decoded — damaged, or written by a newer build — Autheris never saves over them: it shows that the codes can't be read and refuses every change. The user can then choose **Set Aside and Start Over**, which first copies the unreadable data to a Keychain item of its own (`otpCodes.unreadable`, same protection class) and only then starts the vault empty. Nothing reads that item back; it exists so the data isn't destroyed. There is only ever one: setting aside again replaces it. Like the other Keychain items it survives deleting the app.

## App Lock

App Lock (**Settings → Privacy → Require Face ID / Touch ID**) uses `LAPolicy.deviceOwnerAuthentication`, so Face ID or Touch ID with the passcode as the fallback, or Touch ID and the login password on a Mac. The logic is in `Vaultic/AppLockManager.swift`.

- **When it locks.** Every cold launch, and on returning after more than **30 seconds** away. On iOS "away" is the scene reaching the background. A Mac window that loses focus never gets there, so on the Mac the grace period starts when the app resigns active.
- **The Mac Settings window** is a separate window outside the main window group, and shows the same lock screen while the app is locked.
- **Asking again before sensitive actions.** The grace period means a phone unlocked moments ago opens straight into the code list. So with App Lock on, `AppLockManager.reauthenticate(reason:)` asks again before **turning App Lock off**, opening **Backup**, opening **Transfer via QR Code**, and **View Secret**. Each of those either hands over every secret or removes the lock. Cancelling leaves things as they were.

With App Lock off, none of this applies: the user has chosen not to be asked. On a device with no passcode there is nothing to authenticate with, so re-authentication lets the action through.

## Copied codes

`Vaultic/ClipboardHelper.swift` copies a code with `.localOnly`, so Universal Clipboard doesn't carry it to the user's other devices, and with an expiration date **60 seconds** out, so it clears itself. On the Mac it is marked `org.nspasteboard.ConcealedType`, which keeps it out of Universal Clipboard and out of clipboard-history tools that honour the convention. The app clears it after 60 seconds, unless something else has been copied since.

## Backups

**Settings → Data → Backup** writes files to `Documents/OTPBackups`.

- **Encrypted backups** (`.autheris`) use AES-256-GCM with a key from PBKDF2-HMAC-SHA256 (CommonCrypto). The envelope is versioned: version 2 records its iteration count, written as **600,000**. Version 1 files used a fixed 120,000 and still open. The stored count is bounds-checked, so a forged file can't skip the work or hang the app deriving a key. New encrypted backups need a password of at least **10 characters**. See `Vaultic/BackupCrypto.swift`.
- **Unencrypted backups** (`.json`) are plain JSON, which is every secret in readable form. The choice is explicit in the UI, which offers the encrypted backup first.
- **Both kinds stay on the device.** Files are written with `.completeFileProtection` and excluded from iCloud Backup and Finder/iTunes backups (`isExcludedFromBackup`, on the folder and on each file). Backups written by earlier versions get the same treatment at launch. Sharing a backup out of the app is the user's own decision.
- **Restoring replaces everything.** Every restored code is stamped with a fresh `modifiedAt`, so the restore counts as a newer write than any tombstone a later delete left in iCloud and isn't deleted again at the next sync. A file picked from Files is read while its security scope is open and held until the restore is confirmed.

## Imports

Codes from another app's export, an `autheris://` link or a transfer QR code all go through `OTPDataStore.addCodes(_:)`. A link's codes are only added after the user taps **Import**, and never while the app is locked ([GHSA-75h3-q43q-9338](https://github.com/Nerdykidtech/Autheris/security/advisories/GHSA-75h3-q43q-9338)). Each imported code gets a **new UUID and a fresh `modifiedAt`**, because a payload's own values can't be trusted: a reused id would collide with a code already on the device, and a future timestamp would win every sync conflict from then on. A code whose label and account match one already present is skipped, and the count shown is of codes actually added.

**Transfer via QR Code** shows an `autheris://import` link that holds **every secret unencrypted** — anyone who can see or photograph the screen can take the whole vault, which is why it asks for authentication first and the link is dropped as soon as the sheet closes. **Share QR Code** saves or sends the image wherever the user chooses — Messages, Photos (and with it iCloud Photos), AirDrop, Files — where it stays, unencrypted, after the sheet closes; an encrypted backup is the safer way to move codes through anything but a screen. It comes in two formats (`TransferPayload` in `Vaultic/TransferPayload.swift`). Version 1, the full JSON export, is what every release reads, and is used whenever it fits in one QR code. Version 2 (`v=2`) is compact — label, account, the secret as raw bytes, only non-default settings, compressed — and is used for vaults too large for version 1; it needs 2.9 or later to import. A version 2 payload is decoded as untrusted input: every length is checked against the bytes that remain, a count larger than the payload could hold is refused, decompression is capped, trailing bytes are rejected, and the counter is clamped to `OTPCode.maximumCounter` like every other way in. Whatever it decodes to then goes through the same review and `addCodes(_:)` as any other import.

## Apple Watch

The watch app is read-only and generates codes itself from a copy of the list the iPhone sends over WatchConnectivity. It stores that copy in its own Keychain, with the same protection class as the phone. A list too large for an application context is sent as a file. The phone stages that file with `.completeFileProtectionUnlessOpen`, so it is unreadable while the phone is locked but a transfer already in progress can finish, and deletes it once the transfer is done (`WatchRelayStaging` in `Vaultic/Sync/WatchTokenRelay.swift`).

## What the privacy screen covers

The rule lives in `Vaultic/PrivacyShield.swift`, which is pure so it can be unit tested. Content is shielded when either of two things is true:

- **The app is not frontmost** — the app switcher and the home screen. Controlled by *Hide codes in app switcher* (a full cover) and *Blur when backgrounded* (a softer treatment).
- **The screen is being recorded or mirrored**, while the app is still frontmost. This is the case that produces no `scenePhase` change and no "will resign active", so there is nothing for the existing app-lifecycle notifications to hang off. It is observed through `UIScreen.capturedDidChangeNotification` in `Vaultic/ScreenCaptureMonitor.swift` and controlled by *Hide codes while recording or mirroring*.

The two reasons are OR-ed rather than exclusive: a device can be recording while the app sits in the background, and honouring only the app-switcher setting there would leave the recording with a visible — merely blurred — token list. All three toggles default to on.

One thing this cannot cover: **a screenshot**. iOS posts no notification for one, because it is a single frame taken without the app's involvement, so the capture protection does not apply to it and the app does not claim otherwise.

## Recently Deleted

Deleting a code moves a copy into **Recently Deleted** (**Settings → Data → Recently Deleted**), where it stays recoverable for **7 days** and is then removed for good. The window and the restore rules live in `Vaultic/TrashBin.swift`, which is pure so both can be unit tested.

The trash is deliberately **local to the device and never synced**. A delete still writes a tombstone immediately, so the code disappears from the user's other devices straight away — the trash does not delay or soften that. Restoring puts the code back stamped with a fresh `modifiedAt`, which is what makes the restore a *newer write* than the tombstone it is undoing; without that, the next sync would delete it again.

It is stored in the Keychain under its own account, with the same protection as live codes. The trade-off is explicit: a deleted code's secret stays on the device for those 7 days instead of being gone the moment you tap delete. Use **Delete Now** (swipe a row) or **Delete All** to remove it immediately.

Known gap: restoring a backup replaces the token list wholesale and does **not** route the replaced codes through the trash, so a restore is still irreversible.

## Counter-based codes

Autheris generates two kinds of one-time password, and the difference is not cosmetic:

- **Time-based (TOTP, RFC 6238)** — derived from the clock. What nearly every service uses. The code is replaced by the next one when its period runs out, and the card counts that period down.
- **Counter-based (HOTP, RFC 4226)** — derived from a **counter the user moves**. The code does not expire; it stays valid until it is spent. The card shows the counter instead of a countdown and carries a **Next Code** button, and the context menu has the same action for the times the button is covered.

Both are the same HMAC construction with a different counter, which is why they share one generator: `OTPGenerator.generateOTP` derives its counter from the clock and `generateHOTP` takes one. They are deliberately the same code path from the HMAC onwards (`OTPGenerator.generate`), so they cannot drift apart in the dynamic truncation or the padding — `VaulticTests/OTPGeneratorTests.swift` pins the seam.

What `OTPKind` and `OTPCode.counter` are for:

- The **counter is user state**, so it persists, syncs, travels in backups and QR exports, and crosses to the watch. A code that lost its counter would start generating time-based codes the service rejects, with nothing on screen looking wrong.
- **Advancing is explicit, never automatic.** Copying a code does not spend it: a copy is not evidence the service accepted it, and a counter spent by accident is a code the user can no longer read off the screen to retype. The only paths that advance it are the card's button, its context menu, and the counter stepper in **Edit** (which exists to catch up a counter the service has moved past).
- The counter is capped at `OTPCode.maximumCounter`, `Int64.max` — the largest value the CloudKit `counter` field carries back. `OTPAuthURLParser` and the import parsers clamp to it rather than trusting a number a stranger wrote into a QR code or a backup.
- **The watch shows it and cannot move it.** The watch app is read-only by design and advancing is a write, so a counter-based page says which counter it is and that advancing happens on the iPhone.
- **Sync of the counter is best effort.** Two devices that each spend a code before syncing produce two different counters and the newer `modifiedAt` wins, so one increment is lost; the service usually accepts a few counters ahead, and **Next Code** is there if it does not. This is the same last-write-wins rule the rest of sync uses, applied to a field where the "loser" is a spent code rather than an edit — worth knowing before reporting a code that "stopped working" on a second device.

Imports: Aegis and andOTP HOTP entries are imported with their counters, and so are Google Authenticator's (its export has carried HOTP entries all along; the parser used to drop them silently). 2FAS HOTP entries are still skipped — see the note on `ExternalImportParser`.

## What iCloud Sync sends, and how

Sync is opt-in and only ever uses the **private** CloudKit database, which is scoped to the signed-in iCloud account and is not readable by the developer.

- `label`, `account`, `secret`, `timerRingHex` and `isPinned` are written exclusively through `CKRecord.encryptedValues`, so CloudKit encrypts them end to end with keys it manages on the user's behalf. They never appear as readable fields and are not visible in the CloudKit dashboard. (`isPinned` is not a secret, but it is still a statement about which accounts matter to this user, so it is encrypted alongside the label rather than left readable on Apple's servers.)
- Only `modifiedAt`, `deleted`, `fingerprint`, `algorithm`, `digits`, `period`, `kind` and `counter` are plain fields. None of them reveal a secret: `kind` says whether the code is time- or counter-based and `counter` how many times it has been used, neither of which describes the account; `fingerprint` is a SHA-256 over the record content (including the token id, so identical secrets on two records never collide) and is a one-way hash of a high-entropy base32 secret.
- Deleting a token replaces its record with a **tombstone** whose encrypted fields are explicitly cleared, so the secret does not linger in iCloud after a delete.

## Contact

Please report security issues privately via GitHub's
[Report a vulnerability](https://github.com/Nerdykidtech/Autheris/security/advisories/new)
form, or email security@autheris.app. Please don't open a public issue.

Worth including, so the report can be reproduced rather than guessed at:

- **The version and the platform** — the build number from **Settings → About**, and whether
  it is iPhone, iPad, Mac or Apple Watch.
- **What an attacker gains**, not only the mechanism: a secret read out, a code read off a
  locked device, a sync write the user never made. The rest of this document separates
  findings by what physical access they assume, and severity follows that split.
- **The steps**, and whether they need a jailbroken device, a forensic extraction, or
  physical access to an unlocked phone. A finding that presupposes an already-compromised
  device is still worth reporting — it is just a different severity from one that does not.

**We aim to acknowledge a report within 48 hours and give an initial assessment within 5
working days.**

This is a project maintained by one person, so please allow it to be fixed before the finding
is made public. If you hear nothing back, a full inbox is far likelier than a decision to
ignore you — send it again.
