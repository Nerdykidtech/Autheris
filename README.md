<div align="center">

<img src="https://autheris.app/assets/img/app-icon.png" width="128" alt="Autheris app icon">

# Autheris

**A privacy-first two-factor authenticator for iPhone, iPad, Mac and Apple Watch.**

Your codes stay on your device. No account, no server, no tracking.

<a href="https://apps.apple.com/app/id6760686327"><img src="https://img.shields.io/badge/App_Store-Download-0D96F6?style=flat-square&logo=apple&logoColor=white" alt="Download on the App Store"></a>
<img src="https://img.shields.io/badge/iOS_·_iPadOS_·_macOS_·_watchOS-26+-111111?style=flat-square&logo=apple&logoColor=white" alt="iOS, iPadOS, macOS and watchOS 26 or later">
<a href="https://github.com/Nerdykidtech/Autheris/actions/workflows/pr-checks.yml"><img src="https://img.shields.io/github/actions/workflow/status/Nerdykidtech/Autheris/pr-checks.yml?style=flat-square&label=build" alt="Build status"></a>
<img src="https://img.shields.io/badge/Swift-SwiftUI-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift and SwiftUI">
<a href="./LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue?style=flat-square" alt="MIT License"></a>

[Website](https://autheris.app) · [App Store](https://apps.apple.com/app/id6760686327) · [Security model](docs/security.md) · [Changelog](CHANGELOG.md)

<br>

<img src="https://autheris.app/assets/img/og-image.jpg" width="720" alt="Autheris on iPhone, iPad, Mac and Apple Watch">

</div>

---

## Overview

Autheris generates the time-based (TOTP) and counter-based (HOTP) one-time codes that protect your accounts. It keeps the secrets behind them in the system Keychain, on your device. It has no backend of its own, and nothing leaves your device unless you export it or turn on iCloud Sync.

It is one native SwiftUI codebase for every Apple platform: no Catalyst and no stretched iPad app on the Mac.

## Features

**Codes**
- TOTP ([RFC 6238](https://www.rfc-editor.org/rfc/rfc6238)) and HOTP ([RFC 4226](https://www.rfc-editor.org/rfc/rfc4226)), with SHA-1, SHA-256 or SHA-512 and 6–10 digits
- Add accounts by scanning a QR code or picking a screenshot
- Import from Google Authenticator, Aegis, andOTP and 2FAS (counter-based accounts included, except from 2FAS)
- Tap to copy, pin favourites to the top, drag to reorder, search instantly
- Recently Deleted keeps a removed code recoverable on the device for 7 days

**Privacy and security**
- App Lock with Face ID, Touch ID or your passcode. It re-locks 30 seconds after you leave, and asks again before sensitive actions such as exporting, backing up or showing a setup key
- Codes are hidden in the app switcher and while the screen is recorded or mirrored
- Copied codes never sync to your other devices, and the clipboard clears after 60 seconds
- Password-encrypted backups (AES-256-GCM, PBKDF2 with 600,000 iterations) that stay out of iCloud and computer backups
- Optional iCloud Sync, off by default, with secrets end-to-end encrypted in your private CloudKit database

**Everywhere you are**
- iPhone and iPad, with a two-column grid on larger screens
- A native Mac app with a real preferences window
- A read-only Apple Watch app that generates codes on the watch itself, even with your phone out of reach

## Screenshots

<p align="center">
  <img src="screenshots/iphone/autheris-iphone-01-codes.png" width="24%" alt="The iPhone app showing a list of codes">
  <img src="screenshots/ipad/autheris-ipad-01-codes.png" width="48%" alt="The iPad app showing codes in a two-column grid">
  <img src="screenshots/watch/autheris-watch-01-code.png" width="16%" alt="The Apple Watch app showing one code with its countdown">
</p>

<p align="center">
  <img src="screenshots/mac/autheris-mac-01-codes.png" width="32%" alt="The Mac app showing codes in a grid">
  <img src="screenshots/mac/autheris-mac-02-settings.png" width="32%" alt="The Mac preferences window">
  <img src="screenshots/mac/autheris-mac-03-add-token.png" width="32%" alt="Adding an account on the Mac">
</p>

## Security at a glance

| | |
| --- | --- |
| **Storage** | Keychain, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, so secrets are never included in device backups |
| **Network** | No server. The only request the app can make is an optional issuer-icon lookup that sends the service's name, never a secret. It can be turned off in Settings → Privacy |
| **Sync** | Opt-in. CloudKit private database with secrets in end-to-end encrypted fields |
| **Backups** | Optional password encryption (AES-256-GCM). Backup files are file-protected and excluded from device backups |
| **Telemetry** | None. No analytics, no ads, no account |

The full threat model, including what Autheris deliberately does not protect against, is in [`docs/security.md`](docs/security.md).

**Found a vulnerability?** Please report it privately through [GitHub Security Advisories](https://github.com/Nerdykidtech/Autheris/security/advisories/new) rather than in a public issue.

## Building from source

```bash
git clone https://github.com/Nerdykidtech/Autheris.git
cd Autheris
open Vaultic.xcodeproj
```

**Requirements:** Xcode 26 or later with the iOS, macOS and watchOS 26 SDKs. The Mac target needs a provisioning profile for `com.eddingtontech.autheris`. Building once in Xcode while signed in, or with `-allowProvisioningUpdates`, creates it.

**Tech stack:** Swift and SwiftUI, with complete strict concurrency checking · Keychain storage · CloudKit for optional sync · WatchConnectivity for the watch · CryptoKit and CommonCrypto for backups · XCTest.

## Documentation

| Document | Contents |
| --- | --- |
| [`docs/security.md`](docs/security.md) | Threat model: storage, privacy screen, iCloud Sync, issuer icons |
| [`docs/icloud-sync.md`](docs/icloud-sync.md) | Merge rules, the CloudKit container and schema deployment |
| [`docs/platforms.md`](docs/platforms.md) | How the Mac and Apple Watch apps differ from the phone |
| [`docs/development.md`](docs/development.md) | Tests, localisation and project structure |
| [`docs/releasing.md`](docs/releasing.md) | Archiving, exporting and submitting to the App Store |

## Privacy

Autheris collects no data. Read the full [privacy policy](https://autheris.app/privacy).

## License

Released under the [MIT License](./LICENSE).

---

<div align="center">
  <sub>Built by <a href="https://eddington.tech">Hunter Eddington</a>, identity and access management engineer.</sub>
</div>
