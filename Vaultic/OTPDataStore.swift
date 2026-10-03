import Foundation
import Combine

@MainActor
final class OTPDataStore: ObservableObject {
    @Published var codes: [OTPCode] = []
    /// Drives the sync row in Settings. Mirrors the sync service.
    @Published private(set) var syncStatus: CloudSyncStatus = .disabled
    /// Mirrors the `isICloudSyncEnabled` `@AppStorage` key so views can react to it.
    @Published private(set) var isSyncEnabled = false
    /// Whether iCloud is usable right now, so Settings can explain itself.
    @Published private(set) var isSyncAvailable = false
    /// The "Recently Deleted" buffer, newest first is applied by the view. Local
    /// to this device and never synced; see `TrashBin`.
    @Published private(set) var trash: [TrashBin.Entry] = []

    /// `@AppStorage` key shared with Settings. Owned here so the store and the
    /// view cannot drift apart.
    ///
    /// `nonisolated` so it can be used in `@AppStorage` property-wrapper
    /// attributes, which are evaluated outside an actor context.
    nonisolated static let syncEnabledKey = "isICloudSyncEnabled"

    private let saveKey = "otpCodes"
    /// Keychain account for the deletion tombstones — and the `UserDefaults` key
    /// they used to live under, still read once so an upgrade can migrate them.
    /// One constant for both because it is the same logical item; see
    /// `SyncTombstoneStore` for why it had to move.
    private let tombstonesKey = "otpSyncTombstones"
    /// Keychain account for the "Recently Deleted" buffer. Local to this device:
    /// a delete still writes a tombstone, so it propagates as it always did.
    private let trashKey = "otpTrash"
    private let backupDirectory: URL

    /// Deletion tombstones awaiting propagation, keyed by token UUID string.
    /// Needed because a delete has to be able to beat an older edit from a device
    /// that was offline; see `SyncMergeEngine`.
    private var tombstones: [String: Date] = [:]

    private var syncService: TokenSyncService
    private var syncTask: Task<Void, Never>?
    /// Set while a sync is running. A sync requested meanwhile only sets
    /// `needsResync`, and runs once the current one finishes.
    private var isSyncInFlight = false
    private var needsResync = false
    /// Hands the token list to the paired Apple Watch. Inert on the Mac, which has
    /// no watch to talk to.
    private let watchRelay: WatchTokenRelayService

    /// `false` until the tokens, tombstones and trash have actually been read
    /// from the Keychain.
    ///
    /// They are `WhenUnlocked` items, so a launch while the device is locked — a
    /// silent push, say — can't read them, and `codes` is then an empty list
    /// that only *looks* like an empty vault. Until this is set nothing is
    /// saved, synced or offered to the watch, because each of those would treat
    /// that list as the truth: the next save would write it over the real
    /// vault. The load is retried when the device unlocks and when the app
    /// becomes active.
    ///
    /// Published so the token list can say the codes can't be read, instead of
    /// showing an empty vault, and every edit is refused until it is set — an
    /// edit made meanwhile would look saved and then be gone.
    @Published private(set) var isVaultLoaded = false
    /// Whether the tombstones and the trash were readable when the vault loaded.
    ///
    /// The codes decide whether the vault loads at all. These two can't hold it
    /// up — a damaged trash item must not stop anyone reaching their codes — so
    /// an unreadable one loads as empty instead, and is then never written:
    /// writing would replace whatever it still holds.
    private var canPersistTombstones = false
    private var canPersistTrash = false
    /// Set when the codes are stored but won't decode — as opposed to a locked
    /// device, which sorts itself out. Nothing will make these readable short of
    /// a build that understands them, so the token list offers a way forward:
    /// `setAsideUnreadableCodes()`.
    @Published private(set) var hasUnreadableCodes = false
    /// Retry observers for a load that found the Keychain locked.
    ///
    /// `nonisolated(unsafe)` only so `deinit`, which is not main-actor isolated,
    /// can read it. It is written once in `init` and read once in `deinit`.
    nonisolated(unsafe) private var vaultRetryObservers: [NSObjectProtocol] = []
    private let readKeychain: @MainActor (String) -> KeychainStore.ReadResult

    /// - Parameter syncService: injectable so tests can drive the merge path with
    ///   a fake. Defaults to CloudKit, or to a no-op when iCloud Sync is off.
    /// - Parameter watchRelay: injectable for the same reason. Defaults to the
    ///   platform's real relay.
    /// - Parameter readKeychain: injectable so tests can stand in for a locked
    ///   device. Writes still go to the real Keychain.
    init(syncService: TokenSyncService? = nil,
         watchRelay: WatchTokenRelayService? = nil,
         readKeychain: @escaping @MainActor (String) -> KeychainStore.ReadResult = KeychainStore.read(account:)) {
        // Restore Keychain-backed preferences before anything reads UserDefaults.
        PreferencesStore.restoreIntoUserDefaults()

        // Create backup directory if it doesn't exist
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        backupDirectory = documentsDirectory.appendingPathComponent("OTPBackups")

        try? FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        Self.protectBackups(in: backupDirectory)

        let enabled = UserDefaults.standard.bool(forKey: Self.syncEnabledKey)
        isSyncEnabled = enabled
        self.syncService = syncService ?? CloudKitTokenSyncService(isEnabled: enabled)
        // Before `loadVault()`, which saves and therefore pushes: the relay has to
        // exist by then, or the first launch after installing the watch app offers
        // it nothing.
        self.watchRelay = watchRelay ?? WatchTokenRelay.make()
        self.readKeychain = readKeychain

        loadVault()

        let center = NotificationCenter.default
        vaultRetryObservers = AppActivity.keychainMayHaveBecomeReadable.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.retryVaultLoad() }
            }
        }

        self.syncService.onStatusChange = { [weak self] status in
            self?.syncStatus = status
        }
        syncStatus = self.syncService.status

        // Silent pushes arrive through the app delegate, which has no reference to
        // this object; register so it can find us.
        SyncRemoteNotificationRouter.register { [weak self] userInfo in
            await self?.handleRemoteNotification(userInfo) ?? false
        }

        if enabled {
            Task { [weak self] in
                await self?.refreshSyncAvailability()
                await self?.syncNow()
            }
        }
    }

    deinit {
        vaultRetryObservers.forEach(NotificationCenter.default.removeObserver)
    }

    func saveCodes() {
        // Saving before the vault has loaded would replace it with whatever
        // happens to be in memory; see `isVaultLoaded`.
        guard isVaultLoaded else { return }
        // Persist a copy with repeated ids dropped, but don't reassign `codes`
        // here: reassigning during a delete/insert turns one user action into
        // two array mutations, which can make SwiftUI's List diff assert.
        //
        // Only repeated *ids*. Two codes that share a name can hold different
        // secrets, and filtering by name here is how one of them used to vanish
        // on the next save.
        let unique = Self.uniqueIDs(codes)
        if let encoded = try? JSONEncoder().encode(unique) {
            if KeychainStore.save(encoded, account: "otpCodes") {
                // Once the encrypted copy is in place, don't leave a plaintext
                // legacy copy behind.
                UserDefaults.standard.removeObject(forKey: saveKey)
            } else {
                #if DEBUG
                print("Failed to save tokens to Keychain")
                #endif
            }
        }

        // Offer the list to the watch. Sent in *display* order — pinned first,
        // then the user's own arrangement — because the watch has no reordering UI
        // and should show the codes in the order the phone shows them, rather than
        // in the order this array happens to be stored in.
        pushCodesToWatch()
    }

    /// Hands the current codes to the paired watch.
    ///
    /// The single place the order the watch sees is decided, so `saveCodes()` and
    /// the launch-time offer in `init` cannot disagree about it.
    private func pushCodesToWatch() {
        // An unloaded vault would tell the watch to clear its cache.
        guard isVaultLoaded else { return }
        watchRelay.push(TokenOrdering.displayed(codes))
    }

    /// Reads the tokens, tombstones and trash, or leaves everything untouched if
    /// the codes can't be read yet.
    ///
    /// The codes are the vault: if they can't be read — the device is locked, or
    /// they are stored but won't decode — nothing is applied, and nothing will
    /// be saved over them. The tombstones and the trash can't hold the vault up;
    /// see `canPersistTombstones`.
    private func loadVault() {
        guard !isVaultLoaded else { return }
        let storedCodes = readKeychain("otpCodes")
        let decodedCodes: [OTPCode]?
        switch storedCodes {
        case .unavailable(let status):
            #if DEBUG
            print("Keychain not readable yet (status \(status)); deferring the vault load")
            #endif
            return
        case .found(let data):
            guard let decoded = try? JSONDecoder().decode([OTPCode].self, from: data) else {
                // Present but unreadable. Starting empty would save `[]` over it
                // with the first edit, so the vault stays unloaded instead.
                #if DEBUG
                print("The stored codes could not be decoded; leaving them untouched")
                #endif
                hasUnreadableCodes = true
                return
            }
            decodedCodes = decoded
        case .notFound:
            decodedCodes = nil
        }
        finishLoading(with: decodedCodes)
    }

    /// Applies the codes `loadVault` read — `nil` when there were none — and
    /// reads the tombstones and trash alongside them.
    private func finishLoading(with decodedCodes: [OTPCode]?) {
        let storedTombstones = readKeychain(tombstonesKey)
        let storedTrash = readKeychain(trashKey)
        canPersistTombstones = Self.isReadable(storedTombstones)
        canPersistTrash = Self.isReadable(storedTrash)

        isVaultLoaded = true
        hasUnreadableCodes = false
        loadCodes(decodedCodes)
        loadSyncMetadata(from: storedTombstones.data)
        loadTrash(from: storedTrash.data)

        // Offer the loaded list once, whatever path loaded it.
        //
        // `saveCodes()` pushes on every edit, and `loadCodes()` pushes when it
        // *migrates* or finds nothing — but the path a returning user takes, where
        // the Keychain already holds the codes, calls neither. Without this, an
        // app that launches with tokens already stored would never hand the relay
        // anything, and the watch would sit empty until the user happened to edit
        // a token. That is exactly the case for someone who installs the watch app
        // *after* filling the phone, so the missing push is not a rare one.
        pushCodesToWatch()
    }

    /// Moves codes that won't decode out of the way, to a Keychain item of their
    /// own, and starts the vault empty — so a backup can be restored or codes
    /// added again, instead of the app staying unusable.
    ///
    /// Only for `hasUnreadableCodes`, and only on the user's say-so. The bytes are
    /// copied before anything replaces them, and if that copy can't be written
    /// nothing changes. They stay on the device, under an account no other code
    /// reads or writes, rather than being thrown away.
    ///
    /// - Returns: `false` when nothing was changed.
    @discardableResult
    func setAsideUnreadableCodes(now: Date = Date()) -> Bool {
        guard !isVaultLoaded, hasUnreadableCodes,
              case .found(let data) = readKeychain("otpCodes"),
              (try? JSONDecoder().decode([OTPCode].self, from: data)) == nil else { return false }

        // Timestamped, so setting codes aside twice can never overwrite the first.
        let setAside = "otpCodes.unreadable.\(Int(now.timeIntervalSince1970))"
        guard KeychainStore.save(data, account: setAside) else { return false }

        hasUnreadableCodes = false
        finishLoading(with: [])
        // Replace the unreadable copy now, rather than at the next edit.
        saveCodes()
        // With iCloud on, this is how the codes come back.
        if isSyncEnabled {
            Task { [weak self] in await self?.syncNow() }
        }
        return true
    }

    private static func isReadable(_ result: KeychainStore.ReadResult) -> Bool {
        if case .unavailable = result { return false }
        return true
    }

    /// Picks up a load that `init` had to defer because the device was locked,
    /// and runs the sync that was skipped along with it.
    private func retryVaultLoad() {
        guard !isVaultLoaded else { return }
        // The preferences are in the Keychain too, and were just as unreadable.
        PreferencesStore.restoreIfNotYetRead()
        loadVault()
        guard isVaultLoaded, isSyncEnabled else { return }
        Task { [weak self] in
            await self?.syncNow()
        }
    }

    /// `stored` is what the Keychain held, already decoded; `nil` when it held
    /// nothing.
    private func loadCodes(_ stored: [OTPCode]?) {
        // Keychain is authoritative. Fall back to the pre-Keychain UserDefaults
        // blob exactly once, then migrate it and delete the plaintext copy.
        if let stored {
            codes = Self.uniqueIDs(stored)
        } else if let legacyData = UserDefaults.standard.data(forKey: saveKey),
                  let decoded = try? JSONDecoder().decode([OTPCode].self, from: legacyData) {
            codes = Self.uniqueIDs(decoded)
            saveCodes()
        } else {
            // First-time user: no demo or sample tokens
            codes = []
            saveCodes()
        }
    }

    /// Adds one code, or returns `false` without changing anything when one with
    /// the same id or name is already here — which the caller has to say, rather
    /// than closing as if it had worked.
    @discardableResult
    func addCode(_ code: OTPCode) -> Bool {
        // Don't let the same token (or the same id) enter twice; SwiftUI's List
        // diffing crashes on duplicate row identities, and a re-added token
        // would otherwise fight with sync.
        guard isVaultLoaded, !TrashBin.collides(code, with: codes) else { return false }

        codes.append(code)
        // A re-added token must not stay tombstoned, or sync would delete it again.
        tombstones.removeValue(forKey: code.id.uuidString)
        saveCodes()
        persistTombstones()
        scheduleSync()
        return true
    }

    /// Adds codes brought in from outside — a file from another app, an Autheris
    /// link, or a scanned transfer QR code — and reports how many made it in.
    ///
    /// Each code gets a new id and is stamped as edited now. The payload's own
    /// values can't be trusted: a reused id would collide with a code already
    /// here, and a future `modifiedAt` would win every sync conflict from then on.
    /// A code whose label and account match one already here, or one earlier in
    /// the same payload, is skipped and counted as such.
    ///
    /// Returns `nil` when nothing could be added because the vault hasn't loaded
    /// (see `isVaultLoaded`) — which is not the same as every code being a
    /// duplicate, and the caller has to say so.
    @discardableResult
    func addCodes(_ incoming: [OTPCode]) -> (added: Int, skipped: Int)? {
        guard isVaultLoaded else { return nil }
        let now = Date()
        var added: [OTPCode] = []
        for token in incoming {
            let imported = OTPCode(id: UUID(), label: token.label, account: token.account,
                                   secret: token.secret, algorithm: token.algorithm,
                                   digits: token.digits, period: token.period,
                                   kind: token.kind, counter: token.counter,
                                   timerRingHex: token.timerRingHex, isPinned: token.isPinned,
                                   modifiedAt: now)
            guard !TrashBin.collides(imported, with: codes + added) else { continue }
            added.append(imported)
        }

        if !added.isEmpty {
            codes.append(contentsOf: added)
            saveCodes()
            scheduleSync()
        }
        return (added.count, incoming.count - added.count)
    }

    /// Keeps the first token per id: what storage needs, and all it may drop.
    private static func uniqueIDs(_ tokens: [OTPCode]) -> [OTPCode] {
        var seenIDs = Set<UUID>()
        return tokens.filter { seenIDs.insert($0.id).inserted }
    }

    /// Keeps the first of each set of copies (see `OTPCode.isCopy(of:)`).
    ///
    /// Two codes that only share a name both stay: hiding one would hide a
    /// secret, and the user can tell them apart by renaming one.
    private static func withoutCopies(_ tokens: [OTPCode]) -> [OTPCode] {
        // Read on every render, so one pass with two sets rather than comparing
        // each code with all the others.
        var seenIDs = Set<UUID>()
        var seenCopyKeys = Set<String>()
        return tokens.filter { token in
            seenIDs.insert(token.id).inserted && seenCopyKeys.insert(token.copyKey).inserted
        }
    }

    /// The list the token screen renders: pinned first, then everything else, each
    /// group in this device's own order.
    ///
    /// De-duplicated here rather than in the view, because `move` reorders *this*
    /// same array — so the offsets SwiftUI hands back always line up with it.
    var orderedCodes: [OTPCode] {
        TokenOrdering.displayed(Self.withoutCopies(codes))
    }

    /// Whether some *other* code already goes by `code`'s name, which a rename
    /// must not create.
    func nameIsTaken(by code: OTPCode) -> Bool {
        codes.contains { $0.id != code.id && $0.hasSameName(as: code) }
    }

    /// Deletes the tapped token and any copies of it (see `OTPCode.isCopy(of:)`).
    /// The list shows copies as one row, so deleting that row removes them all — but
    /// a different token that only shares the name is left alone.
    func removeCode(_ code: OTPCode) {
        guard isVaultLoaded else { return }
        let removed = codes.filter { $0.isCopy(of: code) }
        guard !removed.isEmpty else { return }

        codes.removeAll { $0.isCopy(of: code) }
        let deletedAt = Date()
        for token in removed {
            tombstones[token.id.uuidString] = deletedAt
            // Keep a recoverable copy for this device. The tombstone above still
            // carries the deletion to the user's other devices straight away —
            // the trash never delays or softens that.
            trash.append(TrashBin.Entry(code: token, deletedAt: deletedAt))
        }
        saveCodes()
        persistTombstones()
        persistTrash()
        scheduleSync()
    }

    // MARK: - Recently Deleted

    /// Puts a trashed token back.
    ///
    /// Returns `.collides` when something already holds the token's id or
    /// label+account, in which case nothing is changed and the caller should say
    /// so rather than leaving a silent no-op.
    @discardableResult
    func restoreFromTrash(_ entry: TrashBin.Entry) -> TrashBin.RestoreOutcome {
        guard isVaultLoaded else { return .collides }
        let outcome = TrashBin.restore(entry, into: codes, at: Date())
        guard case .restored(let restored) = outcome else { return outcome }

        codes.append(restored)
        // The token is live again, so the deletion it was carrying must not be
        // replayed by the next sync.
        tombstones.removeValue(forKey: restored.id.uuidString)
        trash.removeAll { $0.id == entry.id }

        saveCodes()
        persistTombstones()
        persistTrash()
        scheduleSync()
        return outcome
    }

    /// Drops one entry from the trash for good.
    ///
    /// The tombstone is deliberately left alone: that is what keeps the deletion
    /// propagated, and the user has now confirmed they meant it.
    func deletePermanently(_ entry: TrashBin.Entry) {
        guard isVaultLoaded else { return }
        trash.removeAll { $0.id == entry.id }
        persistTrash()
    }

    func emptyTrash() {
        guard isVaultLoaded, !trash.isEmpty else { return }
        trash.removeAll()
        persistTrash()
    }

    /// Drops anything past the retention window. Called on launch, on foreground,
    /// and when the trash is opened, so an entry cannot outlive its window just
    /// because the app happened to stay running.
    func purgeExpiredTrash(now: Date = Date()) {
        guard isVaultLoaded else { return }
        let sweep = TrashBin.sweep(trash, now: now)
        guard sweep.didExpireAnything else { return }
        trash = sweep.kept
        persistTrash()
    }

    private func loadTrash(from data: Data?) {
        trash = TrashBin.decode(data)
        purgeExpiredTrash()
    }

    private func persistTrash() {
        guard isVaultLoaded, canPersistTrash, let data = TrashBin.encode(trash) else { return }
        if !KeychainStore.save(data, account: trashKey) {
            #if DEBUG
            print("Failed to save the trash to Keychain")
            #endif
        }
    }

    /// Replaces the code at `index`, or returns `false` when the edit would give
    /// it a name another code already has.
    @discardableResult
    func updateCode(_ code: OTPCode, at index: Int) -> Bool {
        guard isVaultLoaded, codes.indices.contains(index), !nameIsTaken(by: code) else { return false }
        // Guarantee an edit is a *newer* write than what it replaces, even if a
        // caller handed back a copy that kept the old timestamp.
        codes[index] = code.modifiedAt > codes[index].modifiedAt ? code : code.edited()
        saveCodes()
        scheduleSync()
        return true
    }

    // MARK: - Pin and order

    /// Pins or unpins a code.
    ///
    /// Pinning syncs — it is a property of the code, so it goes through `edited()`
    /// and gets a fresh `modifiedAt` like any other edit. The result is normalised,
    /// which is what keeps an unpinned code where the user left it instead of
    /// teleporting it to the bottom of the list.
    func setPinned(_ isPinned: Bool, for code: OTPCode) {
        guard isVaultLoaded, let index = codes.firstIndex(where: { $0.id == code.id }) else { return }
        guard codes[index].isPinned != isPinned else { return }

        codes[index] = codes[index].edited(isPinned: isPinned)
        codes = TokenOrdering.displayed(codes)
        saveCodes()
        scheduleSync()
    }

    /// Spends a counter-based code and generates the next one.
    ///
    /// This is the whole life cycle of an HOTP code: the counter is the state, and
    /// moving it forward is the equivalent of waiting out a period. Deliberately
    /// *only* reachable from a control the user presses, never from copying the
    /// code — a copy is not evidence that the service accepted it, and a counter
    /// spent by accident is a code the user can no longer read off the screen to
    /// retype. Services usually accept a few counters ahead, so a mistake costs the
    /// code on screen rather than the account, but it is still a mistake.
    ///
    /// Syncs like any other edit: the counter is a property of the code, and a
    /// phone and a watch that disagree about it disagree about which code works.
    func advanceCounter(for code: OTPCode) {
        guard isVaultLoaded, let index = codes.firstIndex(where: { $0.id == code.id }) else { return }
        // A time-based code has no counter to spend, and advancing one would be a
        // no-op that still wrote a new `modifiedAt` — enough to make two devices
        // re-exchange a token for nothing.
        guard codes[index].kind == .hotp else { return }

        codes[index] = codes[index].edited(counter: codes[index].counter + 1)
        saveCodes()
        scheduleSync()
    }

    /// Applies a drag-to-reorder from the token list.
    ///
    /// `offsets` and `destination` index `orderedCodes`, which is what the `List`
    /// was rendered from. Deliberately does **not** call `scheduleSync()`: manual
    /// order is per-device, and syncing it would mean every drag rewrites many
    /// records. See `TokenOrdering`.
    func move(offsets: IndexSet, destination: Int) {
        guard isVaultLoaded else { return }
        let reordered = TokenOrdering.moving(orderedCodes, offsets: offsets, destination: destination)
        applyReorder(reordered)
    }

    /// Applies a drag-to-reorder of one card from the iPad grid.
    ///
    /// The grid picks up a single card rather than a whole row, so the move is
    /// addressed by the id the drag carried rather than by offsets, and
    /// `destination` is where it was dropped in `orderedCodes` — the same array
    /// `move(offsets:destination:)` is addressed in. Like that call, this
    /// deliberately does not sync: manual order is per-device.
    func moveCode(withID id: UUID, toDisplayedIndex destination: Int) {
        guard isVaultLoaded else { return }
        let reordered = TokenOrdering.moving(orderedCodes, id: id, to: destination)
        applyReorder(reordered)
    }

    /// Stores a new order for what the list shows.
    ///
    /// `reordered` is built from `orderedCodes`, which hides copies, so they are
    /// carried over at the end. Dropping them would be a delete with no tombstone:
    /// iCloud would hand them straight back, and the next drag would drop them
    /// again.
    private func applyReorder(_ reordered: [OTPCode]) {
        let shownIDs = Set(reordered.map(\.id))
        let result = reordered + codes.filter { !shownIDs.contains($0.id) }
        guard result != codes else { return }
        codes = result
        saveCodes()
    }

    // MARK: - iCloud Sync

    /// Turns sync on or off. Local tokens are never modified by this call.
    func setSyncEnabled(_ enabled: Bool) {
        guard enabled != isSyncEnabled else { return }
        isSyncEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.syncEnabledKey)
        syncService.setEnabled(enabled)
        syncStatus = syncService.status
        isSyncAvailable = syncService.isAvailable

        if enabled {
            Task { [weak self] in
                await self?.refreshSyncAvailability()
                await self?.syncNow()
            }
        } else {
            syncTask?.cancel()
            syncTask = nil
        }
    }

    /// Tears down sync, optionally removing the iCloud copy first.
    ///
    /// Deletion happens while sync is still enabled because it needs the
    /// CloudKit connection; if it throws, sync is left on rather than half-off so
    /// the user can retry.
    func disableSync(deleteCloudData: Bool) async throws {
        if deleteCloudData {
            try await syncService.deleteRemoteRecords()
            tombstones.removeAll()
            persistTombstones()
        }
        setSyncEnabled(false)
    }

    /// Re-reads whether iCloud can be used, for when Settings appears.
    func refreshSyncAvailability() async {
        await syncService.refreshAvailability()
        isSyncAvailable = syncService.isAvailable
        syncStatus = syncService.status
    }

    /// Runs a sync now, e.g. from the retry button, app foreground, or a push.
    func syncNow() async {
        syncTask?.cancel()
        syncTask = nil
        await performSync()
    }

    /// Coalesces a burst of edits into a single sync.
    private func scheduleSync() {
        guard isSyncEnabled else { return }
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            // Debounce, so importing or adding several tokens in a row is one sync.
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await self?.performSync()
        }
    }

    /// Runs one sync at a time.
    ///
    /// The sync service refuses to start a second sync while one is running, so an
    /// edit made mid-sync used to wait for the next foreground or push before it
    /// was uploaded. Instead it is remembered here, and one more sync runs as soon
    /// as the current one finishes — with a fresh snapshot, so it includes the edit.
    private func performSync() async {
        // Merging against a vault that hasn't loaded would upload its emptiness;
        // `retryVaultLoad()` syncs once it has.
        // Nor against tombstones it couldn't read: a delete made here and not yet
        // uploaded would look like a code iCloud has and this device lacks.
        guard isSyncEnabled, isVaultLoaded, canPersistTombstones else { return }
        guard !isSyncInFlight else {
            needsResync = true
            return
        }
        isSyncInFlight = true
        defer { isSyncInFlight = false }

        repeat {
            needsResync = false
            await syncOnce()
        } while needsResync && isSyncEnabled
    }

    private func syncOnce() async {
        let snapshot = SyncLocalState(tokens: codes, tombstones: tombstones)
        guard let outcome = await syncService.sync(local: snapshot) else {
            isSyncAvailable = syncService.isAvailable
            return
        }
        // Teardown can land while this sync is in flight (turning sync off, or
        // deleting the iCloud copy). Applying the result then would re-persist the
        // tombstones that path just cleared, so re-check before writing anything.
        guard isSyncEnabled else { return }
        isSyncAvailable = syncService.isAvailable
        apply(outcome, snapshot: snapshot)
    }

    /// Folds a merge result back into local storage.
    ///
    /// `snapshot` is what was handed to the sync. Anything that changed locally
    /// since then — a token added, or a token deleted — is not reflected in
    /// `outcome` and has to be carried over rather than overwritten.
    private func apply(_ outcome: SyncMergeOutcome, snapshot: SyncLocalState) {
        // Tombstones written locally while the sync was in flight, and ones
        // cleared locally (a re-add or a restore from the trash).
        let newLocalTombstones = tombstones.filter { snapshot.tombstones[$0.key] == nil }
        let clearedLocalTombstones = Set(snapshot.tombstones.keys).subtracting(tombstones.keys)
        if outcome.didAdoptRemoteChanges {
            // A token deleted locally mid-sync is still in `outcome.tokens`,
            // because the snapshot had it; keep it deleted.
            var merged = outcome.tokens.filter { newLocalTombstones[$0.id.uuidString] == nil }
            // Only tokens added after the snapshot are missing from the outcome
            // for a good reason. A snapshot token the outcome left out was removed
            // by the merge (e.g. a remote tombstone won) and must stay gone.
            let snapshotIDs = Set(snapshot.tokens.map(\.id))
            let outcomeIDs = Set(merged.map(\.id))
            for local in codes where !outcomeIDs.contains(local.id) && !snapshotIDs.contains(local.id) {
                merged.append(local)
            }
            codes = merged
        }
        tombstones = outcome.tombstones
            .merging(newLocalTombstones) { _, new in new }
            .filter { !clearedLocalTombstones.contains($0.key) }
        persistTombstones()
        saveCodes()
    }

    /// Awaits the sync so the caller can report an accurate background-fetch
    /// result to the system instead of claiming data it has not fetched yet.
    private func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) async -> Bool {
        guard syncService.handleRemoteNotification(userInfo: userInfo) else { return false }
        // A vault that hasn't loaded doesn't sync, so there is no new data to
        // report. `retryVaultLoad()` syncs once it has.
        guard isVaultLoaded else { return false }
        await syncNow()
        return true
    }

    private func loadSyncMetadata(from keychain: Data?) {
        let resolution = SyncTombstoneStore.resolve(
            keychain: keychain,
            legacyDefaults: UserDefaults.standard.data(forKey: tombstonesKey)
        )
        tombstones = resolution.tombstones

        if resolution.removeLegacyCopy {
            // Finishes the upgrade to Keychain-backed tombstones — or retries it,
            // if an earlier attempt could not write to the Keychain.
            persistTombstones()
        }
    }

    private func persistTombstones() {
        guard isVaultLoaded, canPersistTombstones,
              let data = SyncTombstoneStore.encode(tombstones) else { return }

        // The legacy `UserDefaults` copy is only dropped once the Keychain write
        // has succeeded, so a failure leaves the data recoverable instead of
        // destroying the only copy of a tombstone.
        if KeychainStore.save(data, account: tombstonesKey) {
            UserDefaults.standard.removeObject(forKey: tombstonesKey)
        } else {
            #if DEBUG
            print("Failed to save sync tombstones to Keychain")
            #endif
        }
    }

    // MARK: - Backup Functions

    /// Creates a backup file with current codes
    func createBackup() -> URL? {
        // An unloaded vault would back up as empty.
        guard isVaultLoaded else { return nil }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let backupName = "otp_backup_\(timestamp).json"
        let backupURL = backupDirectory.appendingPathComponent(backupName)

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(codes)
            try Self.writeBackup(data, to: backupURL)
            return backupURL
        } catch {
            #if DEBUG
            print("Failed to create backup: \(error)")
            #endif
            return nil
        }
    }

    /// Creates a password-encrypted `.autheris` backup with current codes.
    ///
    /// Async because deriving the key takes 600,000 rounds of PBKDF2, which run
    /// off the main actor; see `BackupCrypto`.
    func createEncryptedBackup(password: String) async -> URL? {
        guard isVaultLoaded else { return nil }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let backupName = "otp_backup_\(timestamp).autheris"
        let backupURL = backupDirectory.appendingPathComponent(backupName)

        do {
            let plaintext = try JSONEncoder().encode(codes)
            let encrypted = try await Task.detached(priority: .userInitiated) {
                try BackupCrypto.encrypt(plaintext: plaintext, password: password)
            }.value
            try Self.writeBackup(encrypted, to: backupURL)
            return backupURL
        } catch {
            #if DEBUG
            print("Failed to create encrypted backup: \(error)")
            #endif
            return nil
        }
    }

    /// Writes a backup that stays on this device.
    ///
    /// Backups live in Documents, which iCloud Backup and Finder backups copy by
    /// default. An unencrypted backup holds every secret in plain JSON, so
    /// letting it ride along would undo the `ThisDeviceOnly` Keychain protection
    /// the codes themselves have. Sharing a backup is still the user's call.
    private static func writeBackup(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        excludeFromBackup(url)
    }

    /// Applies the same protection to the backup folder and to backups written by
    /// earlier versions, which had none.
    private static func protectBackups(in directory: URL) {
        excludeFromBackup(directory)
        let existing = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        for url in existing {
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete],
                                                   ofItemAtPath: url.path)
            excludeFromBackup(url)
        }
    }

    private static func excludeFromBackup(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    /// Lists all available backup files
    func listBackups() -> [URL] {
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: backupDirectory,
                                                                       includingPropertiesForKeys: [.creationDateKey],
                                                                       options: .skipsHiddenFiles)
            return fileURLs.filter { ["json", "autheris"].contains($0.pathExtension.lowercased()) }
                .sorted { url1, url2 in
                    let date1 = try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate
                    let date2 = try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate
                    return (date1 ?? Date.distantPast) > (date2 ?? Date.distantPast)
                }
        } catch {
            #if DEBUG
            print("Failed to list backups: \(error)")
            #endif
            return []
        }
    }

    /// The codes in a backup, without touching the vault. Pass the password for
    /// an `.autheris` encrypted backup; a plain `.json` one ignores it.
    ///
    /// Takes the bytes rather than a URL because a file picked from Files can only
    /// be read while its security scope is open, which the caller controls. Runs
    /// off the main actor: an encrypted backup takes 600,000 rounds of PBKDF2 to
    /// open, and a crafted one is allowed to ask for many more.
    nonisolated static func readBackup(_ fileData: Data, isEncrypted: Bool, password: String? = nil) async throws -> [OTPCode] {
        try await Task.detached(priority: .userInitiated) {
            let plaintext: Data
            if isEncrypted {
                guard let password else { throw BackupCrypto.BackupCryptoError.invalidEnvelope }
                plaintext = try BackupCrypto.decrypt(data: fileData, password: password)
            } else {
                plaintext = fileData
            }
            return try JSONDecoder().decode([OTPCode].self, from: plaintext)
        }.value
    }

    /// Replaces every code with a backup's, as read by `readBackup`.
    ///
    /// A code the backup doesn't contain has, as far as the user's devices are
    /// concerned, been deleted: it gets a tombstone so it doesn't reappear from
    /// iCloud, and it goes to Recently Deleted like any other delete, so a restore
    /// from the wrong backup can still be undone here.
    ///
    /// Returns `false`, having changed nothing, when the vault hasn't loaded.
    @discardableResult
    func replaceAll(with backup: [OTPCode]) -> Bool {
        guard isVaultLoaded else { return false }
        let now = Date()
        // Restored tokens are stamped as edited now. They keep the date they had
        // when the backup was made otherwise, and the tombstone a later delete
        // left in iCloud is newer than that — so the next sync would delete
        // them again. Restoring from the trash does the same for the same reason.
        let restoredCodes = backup.map { $0.edited(modifiedAt: now) }
        let restoredIDs = Set(restoredCodes.map(\.id))
        let replaced = codes.filter { !restoredIDs.contains($0.id) }

        codes = restoredCodes
        for token in replaced {
            tombstones[token.id.uuidString] = now
            trash.append(TrashBin.Entry(code: token, deletedAt: now))
        }
        for id in restoredIDs {
            tombstones.removeValue(forKey: id.uuidString)
        }
        saveCodes()
        persistTombstones()
        persistTrash()
        scheduleSync()
        return true
    }

    /// Deletes a backup file
    func deleteBackup(at url: URL) -> Bool {
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            #if DEBUG
            print("Failed to delete backup: \(error)")
            #endif
            return false
        }
    }

    /// Creates JSON data for QR code export
    func exportData() -> Data? {
        guard isVaultLoaded else { return nil }
        do {
            let encoder = JSONEncoder()
            // Compact JSON — pretty printing inflates size and can exceed QR capacity (~3KB).

            // Create export structure with all tokens
            let exportData = ExportData(
                version: "1.0",
                timestamp: Date(),
                tokens: codes
            )

            return try encoder.encode(exportData)
        } catch {
            #if DEBUG
            print("Failed to export data: \(error)")
            #endif
            return nil
        }
    }
}

// MARK: - Export Data Structure

nonisolated struct ExportData: Codable, Sendable {
    let version: String
    let timestamp: Date
    let tokens: [OTPCode]
}
