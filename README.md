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

**Autheris** is a secure, privacy-focused two-factor authentication (2FA) token manager for iOS. Built with SwiftUI and designed with zero-knowledge architecture — your tokens never leave your device unless you explicitly choose to export them.

## Features

- 🔐 **Privacy-First Design**: Blur app content when backgrounded, hide codes in app switcher
- 👁️ **Setup Key Access**: View, copy, or edit a token's secret — masked by default, tap to reveal
- 📱 **iOS Native**: Built with SwiftUI for the best native experience
- 📸 **QR Code Scanning**: Quick token setup from any 2FA QR code
- 📤 **Export & Backup**: Encrypted backups you control
- 📥 **Easy Migration**: Import from Google Authenticator
- 🔍 **Quick Search**: Find tokens instantly
- 🎨 **Clean Interface**: Simple, distraction-free design

## Tech Stack

- **Language**: Swift 5.9+
- **Framework**: SwiftUI
- **Architecture**: MVVM with Combine
- **Storage**: Secure Enclave (Keychain)
- **Backend**: Cloudflare Workers (optional sync features)

## Security

Autheris is designed with security at its core:

- Tokens stored in iOS Keychain with highest security class
- No account required — fully offline by default
- No analytics or tracking
- No cloud storage unless explicitly enabled
- Open source for transparency

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
