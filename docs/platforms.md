# Platforms

The Mac and Apple Watch apps, and how they differ from the phone.

# macOS

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

## Submitting the Mac app

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

# watchOS

Autheris ships a native watch app. It is a second Xcode target, **`VaulticWatch`**, embedded in the iPhone app at `Autheris.app/Watch/Autheris.app` — a real SwiftUI app built for the watch, not a WatchKit extension hosting a scaled-down phone UI.

It is a **viewer and nothing else**. There is no add, no edit, no delete, no search, no settings, and no copy anywhere in it. Every one of those lives on the iPhone; the watch exists so a code can be read without taking the phone out of a pocket. One code fills the screen, and turning the Digital Crown pages between them.

## How the codes get there

Over **`WatchConnectivity` from the iPhone app** — deliberately *not* over iCloud. That choice is what makes the watch work for every user rather than only for the ones who turned iCloud Sync on, since iCloud Sync is off by default and the two features are otherwise unrelated. The iPhone stays the single source of truth; the watch never writes anything back.

There is no "send codes to my watch" setting, because **installing the watch app is the opt-in**: the phone only sends to a watch it reports as paired *with the app installed* (`WCSession.isPaired && isWatchAppInstalled`). A user who has not chosen to put Autheris on their wrist never has a secret leave the phone. That is the same spirit as iCloud Sync being off until asked for — with the request made by installing the app rather than by flipping a switch.

## Why an application context, and why there is a second transport

The relay uses `WCSession.updateApplicationContext`, the one `WatchConnectivity` transport that describes *state* rather than events. It keeps only the newest dictionary, delivers it whenever the watch app is next reachable — running or not — and leaves it there for the watch to read on its next launch. A token list is exactly that shape: twenty edits while the user is in the app should arrive as one current list, not as a queue of twenty stale ones.

An application context is capped in size and the system **rejects an oversized one outright** rather than truncating it, so a very large token list would silently never reach the watch. Past the cap the relay hands over a file instead. Both transports carry the same `sentAt` stamp (`WatchTokenPayload`), because nothing orders the two against each other — the payload is versioned and time-stamped so the watch applies whichever it sees last and cannot be rolled back by an older list arriving late. That is the same last-write-wins rule `SyncMergeEngine` uses for iCloud, for the same reason.

## What lives where

| Path | What it is |
| --- | --- |
| `Shared/` | One implementation of the OTP core, compiled into **both** targets: `OTPCode`, `OTPGenerator`, `OTPAlgorithm`, `OTPKind`, `ColorHex`, `KeychainStore`, and `WatchTokenPayload`. A `PBXFileSystemSynchronizedRootGroup` listed in each target's `fileSystemSynchronizedGroups`, so a file added here joins both builds. |
| `VaulticWatch/` | The watch app: `AutherisWatchApp` (the scene), `WatchSessionModel` (the `WCSession` receiver), `WatchRootView` (paging and the empty states), `WatchCodePageView` (one code, its countdown, or its counter). |
| `Vaultic/Sync/WatchTokenRelay.swift` | The iPhone half. A `WatchTokenRelayService` protocol with a real `WatchConnectivity` implementation on iOS and an inert one elsewhere, so `OTPDataStore` — which is built on every platform — needs no `#if` at the call site. `OTPDataStore.saveCodes()` pushes from exactly one place. |

The watch does **not** reorder anything. Pinned-first ordering and the user's manual arrangement are the phone's (`TokenOrdering`), and the list arrives already sorted, so the two devices cannot disagree about what order the codes are in.

## When the phone actually sends

Two things about the send are easy to get wrong, and both were caught by running the app against a paired watch rather than by reading the code:

- **The list is offered once at launch, not only on edits.** `saveCodes()` is the obvious single push site, but the path a returning user takes — `loadCodes()` finding the codes already in the Keychain — calls `saveCodes()` *not at all*. Pushing only from there meant an app that launched with tokens already stored handed the relay nothing, so the watch stayed empty until the user happened to edit a token. That is precisely the case for someone who installs the watch app *after* filling their phone, so `OTPDataStore.init` offers the loaded list explicitly.
- **A deferred offer is picked up on foreground, not only by the activation callback.** The launch-time offer always arrives before `WCSession` has finished activating, so something has to pick it up afterwards. `activationDidCompleteWith` is the natural candidate and is **not** reliable — it was observed to never arrive at all on some launches, leaving the watch on a stale list with nothing logged anywhere. The relay therefore also re-offers on `AppActivity.didBecomeActive`, which the system definitely delivers, and the app foregrounds immediately after launch.

`WatchTokenPayloadTests` covers the payload those two triggers carry; the triggers themselves are exercised by running the app against a paired watch simulator.

## Where the watch's copy lives

The system re-delivers the last application context on activation, so the obvious design is to render `receivedApplicationContext` and be done. That is not good enough for a credential app: the redelivery is framework behaviour rather than a documented guarantee, and the failure mode if it changes is a user reaching for their watch and seeing **no codes**, with no explanation. The last list received is therefore written to the watch's own Keychain with the same `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` protection the phone uses, so the app opens on the real codes from the first frame whether or not the phone is anywhere near.

The consequence worth being explicit about: **the codes are on the watch**, because a code cannot be shown without its secret. A paired, unlocked watch is now another place a token exists.

## Deliberate differences from the phone

- **The countdown ring uses the token's own colour or the accent.** The phone additionally falls back to an issuer brand colour from `IssuerBranding` — a type that also carries logo fetching and its caches, none of which belongs on a watch. A token with no custom colour is the accent on the watch and a brand colour on the phone.
- **Codes are generated on the watch, from the tick that draws them.** `WatchCodePageView` drives a `TimelineView` anchored at the epoch, so a tick lands exactly on the TOTP period boundary; the code and the countdown beside it are for the same instant and cannot disagree by a frame. The "about to expire" red matches `HomeView`'s rule (five seconds, or a sixth of a longer period) so both devices turn red together. A counter-based token gets no timeline at all — there is nothing to tick towards, and a once-a-second wake for a page that cannot change is battery on a watch — so it is redrawn when the phone sends a new payload.
- **A counter-based code can be read here but not advanced.** Advancing is a write, and the watch has no writes by design, so the page shows which counter it is and says to advance it on the iPhone. A stale counter is therefore possible on the watch until the phone relays the new one, which it does on the edit within seconds.
- **There is no app lock, no privacy blur and no screen-capture protection.** A watch screen is off unless the wrist is turned, which is a stronger control than the phone's, and the watch app has no UI that could set such a preference.

## Project configuration

| Setting | Value |
| --- | --- |
| Target | `VaulticWatch`, `PRODUCT_NAME = Autheris`, `PRODUCT_MODULE_NAME = AutherisWatch` |
| Bundle id | `com.eddingtontech.autheris.watchkitapp` — the `watchkitapp` suffix is what makes iOS treat it as the companion rather than a second app |
| Companion | `WKCompanionAppBundleIdentifier = com.eddingtontech.autheris` in `VaulticWatch/Info.plist`, plus `WKApplication = true` for a watch app that carries its own UI. `WKWatchOnly` is intentionally **not** set: the watch app is installed from the Watch app, so it needs no App Store listing of its own |
| Platform | `SDKROOT = watchos`, `WATCHOS_DEPLOYMENT_TARGET = 26.0`, `TARGETED_DEVICE_FAMILY = 4` |
| Entitlements | None. No iCloud, no push, no app group — the watch app talks only to its companion and its own Keychain |

Two things about the target wiring are load-bearing and easy to undo by accident:

- The "Embed Watch Content" copy phase and the `PBXTargetDependency` on `VaulticWatch` both carry `platformFilters = (ios, )`. Without them a **Mac** build would try to build the watch app (whose `SUPPORTED_PLATFORMS` is `watchos watchsimulator`) and embed it into the Mac bundle. The Mac app has no `Watch/` directory, and that is the check that the filter is still doing its job.
- `VaulticWatch/Info.plist` is excluded from its folder's synchronized group by a `PBXFileSystemSynchronizedBuildFileExceptionSet`, exactly as `Vaultic/Info.plist` is. Without the exception the plist is copied into the bundle as a *resource* alongside the generated one.

Verify a watch change with:

```bash
xcodebuild -project Vaultic.xcodeproj -scheme VaulticWatch \
  -destination 'generic/platform=watchOS' build CODE_SIGNING_ALLOWED=NO
```

Building the `Vaultic` scheme for iOS or an iOS Simulator destination builds the watch app too and embeds it, so that is the check that the two fit together. Note that running the watch app needs a **watchOS simulator runtime**, which is a separate download from the SDK — the watch app targets watchOS 26, so a watchOS 26 or later runtime.
