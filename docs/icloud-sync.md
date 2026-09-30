# iCloud Sync

The optional sync: what it sends, what the container needs, and how to deploy the schema.

# iCloud Sync

Sync is a per-device setting in **Settings → iCloud Sync**. When it is off, CloudKit is never contacted. When it is on:

- **Add / edit** a token on one device and it appears on the others; the newest edit wins (`OTPCode.modifiedAt`), with a deterministic tie-break if two devices edited at the same instant.
- **Delete** a token anywhere and it is removed everywhere. Deletes are tombstones rather than record removals, so a delete always beats an older edit from a device that was offline, and the tombstones themselves are kept in the Keychain so they survive an app reinstall. The one exception: a device that stayed offline longer than the 30-day tombstone retention and still holds a live copy can reintroduce the token — the deliberate trade-off for not carrying deletion bookkeeping on every device forever.
- **Status** is shown in Settings: `Synced` (with a relative "last updated"), `Syncing…`, `Sync Paused` when offline, `Sign in to iCloud`, or `Sync unavailable` when the build or container is not configured.
- **Failures never block the app.** Local tokens are always authoritative for the device on screen; a failed sync is retried on the next edit, on foreground, or on a silent push.
- **Turning sync off** asks what to do: keep the tokens on this device (default) or delete the iCloud copy first, which also removes them from the other devices. That deletion sweeps every record type the app has ever written, including the [legacy one](#the-legacy-autherissyncrecord-type).
- **Pinning syncs; the manual order does not.** A pin is a property of the code (`OTPCode.isPinned`) and travels like any other edit. The order you drag codes into is per-device, like arranging app icons — the rules live in `Vaultic/TokenOrdering.swift`. Syncing the order would mean a `sortIndex` field, and a single drag would then rewrite many records at once, bumping each `modifiedAt` and letting a concurrent edit on another device silently drop the reorder.

Remote changes arrive via a `CKDatabaseSubscription` silent push (`AppDelegate` → `SyncRemoteNotificationRouter` → `OTPDataStore`), with a foreground sync as the fallback for anything missed.

## Required project configuration

The target already declares these; they are listed so a new machine or a fresh Apple Developer account can reproduce them.

| Setting | Value |
| --- | --- |
| iCloud container | `iCloud.com.eddingtontech.autheris` (must match `CloudKitTokenSyncService.containerIdentifier`) |
| Entitlements file | `Vaultic/Vaultic.entitlements` (wired up via `CODE_SIGN_ENTITLEMENTS`) |
| Capabilities | iCloud → CloudKit, Push Notifications, Background Modes → Remote notifications |
| `UIBackgroundModes` | `remote-notification` (in `Vaultic/Info.plist`) |
| `aps-environment` | `$(APS_ENVIRONMENT)` — `development` for Debug, `production` for Release |

The container identifier in `Vaultic.entitlements` is tied to the `com.eddingtontech.autheris` bundle id and the `37GWLWW278` team. Forking this project means creating your own container and updating both the entitlements file and `CloudKitTokenSyncService.containerIdentifier`.

## Deploying the CloudKit schema

Records use the record type **`AutherisToken`** in the private database. In development, CloudKit creates the schema implicitly on the first successful save — no manual setup is needed to run from Xcode. Before shipping, or if `/usr/bin/log` shows `did not find record type: AutherisToken`:

1. Open the CloudKit Console for the container.
2. Confirm `AutherisToken` exists with fields `modifiedAt` (Date), `deleted` (Int64), `fingerprint` (String), `algorithm` (String), `digits` (Int64), `period` (Int64), `kind` (String), `counter` (Int64), plus the encrypted fields `label`, `account`, `secret`, `timerRingHex`, `isPinned`. In the app these names live in exactly one place — the nested `CloudKitTokenSyncService.Field` enum, whose `plain` / `encrypted` / `all` lists are the authoritative form of this table. Compare the Console against *that*, not against a copy of this README: a CloudKit field name is a string, so a typo silently creates a new field instead of failing to compile, and a field that should be encrypted but is written plainly ends up readable on Apple's servers.

**Every encrypted field holds a String.** `label`, `account`, `secret`, `timerRingHex` and `isPinned` are all String-typed in the Console — including `isPinned`, which stores `"1"` / `"0"` (see `EncryptedBool`). Give the new field the same type the Console already shows for `timerRingHex` rather than a numeric one for the boolean: that is the only encrypted shape exercised against the production container, and CloudKit fixes a field's type once it exists, so a wrong choice can only be undone by picking a different field name.
3. **Add a Queryable index on `recordName`** — see below. This is not optional and is the step most likely to be missed.
4. Deploy the schema from the development environment to production.

A first sync against a container that has never stored a record is expected to find no record type; `CloudKitTokenSyncService` treats that as "no records" rather than an error, so the very first sync still bootstraps.

### Upgrading a container that already holds records

Every release that adds a field changes the `AutherisToken` schema, so an existing container needs the new field deployed (step 2 above covers what to check). Four consequences worth expecting, none of which needs code changes:

- **A field that is absent from existing records reads as its default.** `CloudKitTokenSyncService.decode` treats a missing `isPinned` as unpinned, a missing `kind` as time-based and a missing `counter` as 0, and `OTPCode`'s hand-written decoder does exactly the same for a local token persisted before either existed. Nothing has to be back-filled.
- **The value is a String (`"1"` / `"0"`), not a number**, for every *encrypted* field — `EncryptedBool` owns both directions and reads leniently, so an integer-typed field left over from a development experiment still reads correctly rather than reporting every pin as `false`. The plain fields keep the types the table above names: `kind` is a String holding `TOTP` / `HOTP`, and `counter` an Int64, which is why `OTPCode.maximumCounter` is `Int64.max` — a larger counter would be written as one number and read back as another.
- **`SyncFingerprint`'s canonical version moves whenever a field joins it** — `v1` → `v2` when `isPinned` arrived, → `v3` when `kind` and `counter` did, because a fingerprint has to see every field the user can change. Otherwise toggling a pin, or spending a code, would look like "no change" and never sync. Every token's fingerprint therefore differs from the value its iCloud record still carries, so the first sync after upgrading re-exchanges each record once and settles. That is expected and one-time. **The counter is the case where this is not bookkeeping:** a fingerprint that ignored it would leave the device the user is *not* holding generating the code they just spent.
- **A counter-based token on the watch needs the watch app updated too.** `WatchTokenPayload.version` moved from 1 to 2 for this reason: a watch still on 1 refuses the payload rather than decoding a counter-based token as a time- or counter-based one it cannot honour. It keeps showing the list it already had until its own app updates, which is a watch that is briefly out of date rather than one showing codes that cannot work.

If a new field already exists in your development container with the wrong type, delete it and let the next save recreate it — CloudKit will not change a field's type in place.

### The `recordName` index is required

Sync reads the private database with an unfiltered `CKQuery` (`NSPredicate(value: true)`). CloudKit refuses that unless the system `recordName` field carries a **Queryable** index, failing with `Field 'recordName' is not marked queryable`.

**CloudKit creates no indexes on a record type that was created implicitly by saving**, so the sequence is: the first sync writes records successfully (creating `AutherisToken`), and the *next* query fails. Nothing in the app can work around this — it is a schema property. In the Console:

1. **Schema → Indexes**, and select the record type.
2. **Add Basic Index** → select the metadata entry (`__recordID`, which displays as `recordName`).
3. Set **Index Type = Queryable** → **Save Changes**.
4. Repeat for **every** record type the app queries — `AutherisToken` and, if present, the legacy `AutherisSyncRecord` (the delete sweep queries it).
5. **Deploy to production.** Development indexes do not carry over on their own, and there are reports of these metadata index changes being omitted from a deploy diff — so verify in a TestFlight build before release, not just in the Console.

Until the index exists, the Settings row reports "Sync unavailable" with this reason rather than a generic failure.

## The legacy `AutherisSyncRecord` type

A sync implementation was built on a branch, later reverted, and never shipped. Because CloudKit keeps the development schema once a record type has been written, a container used during that work still contains a second type, **`AutherisSyncRecord`**, with a different field set (`kind`, `updatedAt`, `contentHash`, `settingKey`, `value`, and a *plain* `timerRingHex`).

The current app never reads or migrates it — the merge engine only ever sees `AutherisToken`, so the two types cannot interfere. It matters for one reason: those rows can hold real (encrypted) token secrets from the abandoned build, so **Settings → iCloud Sync → Delete Tokens from iCloud sweeps both types**, otherwise a user's request to remove their iCloud copy would leave a copy behind that nothing in the app can reach. If you see that type in the Console, that is expected; do not deploy it to production.
