# Autheris

<p align="center">
  <img src="https://eddington.tech/autheris/og-image.png" alt="Autheris - Secure 2FA Token Manager for iOS" width="600">
</p>

<p align="center">
  <a href="https://apps.apple.com/app/autheris">
    <img src="https://img.shields.io/badge/Download_on_the_App_Store-0D96F6?style=for-the-badge&logo=apple&logoColor=white" alt="Download on the App Store">
  </a>
  <img src="https://img.shields.io/badge/iOS-16.0%2B-000000?style=for-the-badge&logo=ios" alt="iOS 16.0+">
  <img src="https://img.shields.io/badge/SwiftUI-FA7343?style=for-the-badge&logo=swift&logoColor=white" alt="SwiftUI">
</p>

**Autheris** is a secure, privacy-focused two-factor authentication (2FA) token manager for iOS. Built with SwiftUI and designed with zero-knowledge architecture — your tokens never leave your device unless you explicitly choose to export them or turn on iCloud Sync.

## Features

- 🔐 **Privacy-First Design**: Blur app content when backgrounded, hide codes in app switcher
- 👁️ **Setup Key Access**: View, copy, or edit a token's secret — masked by default, tap to reveal
- ☁️ **Optional iCloud Sync**: Off by default. When enabled, tokens sync across your own devices through your private iCloud database, with secret keys end-to-end encrypted
- 📱 **iOS Native**: Built with SwiftUI for the best native experience
- 📸 **QR Code Scanning**: Quick token setup from any 2FA QR code
- 📤 **Export & Backup**: Local backup files and QR exports you control (stored in the app sandbox, protected by the device passcode, not additionally encrypted)
- 📥 **Easy Migration**: Import from Google Authenticator
- 🔍 **Quick Search**: Find tokens instantly
- 🎨 **Clean Interface**: Simple, distraction-free design

## Tech Stack

- **Language**: Swift 5.9+
- **Framework**: SwiftUI
- **Architecture**: MVVM with Combine
- **Storage**: JSON in the iOS Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`). See [Security](#security) for what this does and does not protect
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

### What iCloud Sync sends, and how

Sync is opt-in and only ever uses the **private** CloudKit database, which is scoped to the signed-in iCloud account and is not readable by the developer.

- `label`, `account`, `secret` and `timerRingHex` are written exclusively through `CKRecord.encryptedValues`, so CloudKit encrypts them end to end with keys it manages on the user's behalf. They never appear as readable fields and are not visible in the CloudKit dashboard.
- Only `modifiedAt`, `deleted`, `fingerprint`, `algorithm`, `digits` and `period` are plain fields. None of them reveal a secret: `fingerprint` is a SHA-256 over the record content (including the token id, so identical secrets on two records never collide) and is a one-way hash of a high-entropy base32 secret.
- Deleting a token replaces its record with a **tombstone** whose encrypted fields are explicitly cleared, so the secret does not linger in iCloud after a delete.

## iCloud Sync

Sync is a per-device setting in **Settings → iCloud Sync**. When it is off, CloudKit is never contacted. When it is on:

- **Add / edit** a token on one device and it appears on the others; the newest edit wins (`OTPCode.modifiedAt`), with a deterministic tie-break if two devices edited at the same instant.
- **Delete** a token anywhere and it is removed everywhere. Deletes are tombstones rather than record removals, so a delete always beats an older edit from a device that was offline. The one exception: a device that stayed offline longer than the 30-day tombstone retention and still holds a live copy can reintroduce the token — the deliberate trade-off for not carrying deletion bookkeeping on every device forever.
- **Status** is shown in Settings: `Synced` (with a relative "last updated"), `Syncing…`, `Sync Paused` when offline, `Sign in to iCloud`, or `Sync unavailable` when the build or container is not configured.
- **Failures never block the app.** Local tokens are always authoritative for the device on screen; a failed sync is retried on the next edit, on foreground, or on a silent push.
- **Turning sync off** asks what to do: keep the tokens on this device (default) or delete the iCloud copy first, which also removes them from the other devices. That deletion sweeps every record type the app has ever written, including the [legacy one](#the-legacy-autherissyncrecord-type).

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
2. Confirm `AutherisToken` exists with fields `modifiedAt` (Date), `deleted` (Int64), `fingerprint` (String), `algorithm` (String), `digits` (Int64), `period` (Int64), plus the encrypted fields `label`, `account`, `secret`, `timerRingHex`. In the app these names live in exactly one place — the nested `CloudKitTokenSyncService.Field` enum, whose `plain` / `encrypted` / `all` lists are the authoritative form of this table. Compare the Console against *that*, not against a copy of this README: a CloudKit field name is a string, so a typo silently creates a new field instead of failing to compile, and a field that should be encrypted but is written plainly ends up readable on Apple's servers.
3. **Add a Queryable index on `recordName`** — see below. This is not optional and is the step most likely to be missed.
4. Deploy the schema from the development environment to production.

A first sync against a container that has never stored a record is expected to find no record type; `CloudKitTokenSyncService` treats that as "no records" rather than an error, so the very first sync still bootstraps.

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

There is no test target in this project yet. The conflict-resolution rules, which are where the interesting correctness lives, are isolated in `Vaultic/Sync/SyncMergeEngine.swift` as a pure enum with no I/O and no clock reads (`now` and `tombstoneRetention` are parameters). To exercise it standalone, compile it with the model files and a small harness:

```bash
REPO=/path/to/Autheris
WORK=$(mktemp -d)
cp "$REPO/Vaultic/OTPAlgorithm.swift" "$REPO/Vaultic/OTPCode.swift" \
   "$REPO/Vaultic/OTPGenerator.swift" "$REPO/Vaultic/Sync/SyncMergeEngine.swift" "$WORK/"
# add your own main.swift in $WORK, then:
xcrun swiftc -o "$WORK/checks" "$WORK"/*.swift && "$WORK/checks"
```

Cases worth asserting, all of which follow directly from `SyncMergeEngine.merge`:

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

`OTPCode`'s hand-written `init(from:)` is what keeps pre-sync JSON decodable; keep a case that decodes JSON with no `modifiedAt` key whenever that type changes.

## Installation

```bash
git clone https://github.com/nerdykidtech/Autheris.git
cd Autheris
open Vaultic.xcodeproj
```

Requires Xcode 15.0+ and iOS 16.0+.

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
