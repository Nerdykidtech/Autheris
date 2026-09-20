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

    /// `@AppStorage` key shared with Settings. Owned here so the store and the
    /// view cannot drift apart.
    ///
    /// `nonisolated` so it can be used in `@AppStorage` property-wrapper
    /// attributes, which are evaluated outside an actor context.
    nonisolated static let syncEnabledKey = "isICloudSyncEnabled"

    private let saveKey = "otpCodes"
    private let tombstonesKey = "otpSyncTombstones"
    private let backupDirectory: URL

    /// Deletion tombstones awaiting propagation, keyed by token UUID string.
    /// Needed because a delete has to be able to beat an older edit from a device
    /// that was offline; see `SyncMergeEngine`.
    private var tombstones: [String: Date] = [:]

    private var syncService: TokenSyncService
    private var syncTask: Task<Void, Never>?

    /// - Parameter syncService: injectable so tests can drive the merge path with
    ///   a fake. Defaults to CloudKit, or to a no-op when iCloud Sync is off.
    init(syncService: TokenSyncService? = nil) {
        // Restore Keychain-backed preferences before anything reads UserDefaults.
        PreferencesStore.restoreIntoUserDefaults()

        // Create backup directory if it doesn't exist
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        backupDirectory = documentsDirectory.appendingPathComponent("OTPBackups")

        try? FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)

        let enabled = UserDefaults.standard.bool(forKey: Self.syncEnabledKey)
        isSyncEnabled = enabled
        self.syncService = syncService ?? CloudKitTokenSyncService(isEnabled: enabled)

        loadCodes()
        loadSyncMetadata()

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

    func saveCodes() {
        // Persist a deduplicated copy, but don't reassign `codes` here:
        // reassigning during a delete/insert turns one user action into
        // two array mutations, which can make SwiftUI's List diff assert.
        let deduped = Self.deduplicated(codes)
        if let encoded = try? JSONEncoder().encode(deduped) {
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
    }

    func loadCodes() {
        // Keychain is authoritative. Fall back to the pre-Keychain UserDefaults
        // blob exactly once, then migrate it and delete the plaintext copy.
        if let data = KeychainStore.load(account: "otpCodes"),
           let decoded = try? JSONDecoder().decode([OTPCode].self, from: data) {
            codes = Self.deduplicated(decoded)
        } else if let legacyData = UserDefaults.standard.data(forKey: saveKey),
                  let decoded = try? JSONDecoder().decode([OTPCode].self, from: legacyData) {
            codes = Self.deduplicated(decoded)
            saveCodes()
        } else {
            // First-time user: no demo or sample tokens
            codes = []
            saveCodes()
        }
    }

    func addCode(_ code: OTPCode) {
        // Don't let the same token (or the same id) enter twice; SwiftUI's List
        // diffing crashes on duplicate row identities, and a re-added token
        // would otherwise fight with sync.
        let isDuplicate = codes.contains {
            $0.id == code.id || ($0.label == code.label && $0.account == code.account)
        }
        guard !isDuplicate else { return }

        codes.append(code)
        // A re-added token must not stay tombstoned, or sync would delete it again.
        tombstones.removeValue(forKey: code.id.uuidString)
        saveCodes()
        persistTombstones()
        scheduleSync()
    }

    /// Keeps the first token per id and per label+account pair.
    private static func deduplicated(_ tokens: [OTPCode]) -> [OTPCode] {
        var seenIDs = Set<UUID>()
        var seenKeys = Set<String>()
        var result: [OTPCode] = []
        for token in tokens {
            let key = "\(token.label.lowercased())|\(token.account.lowercased())"
            guard seenIDs.insert(token.id).inserted, seenKeys.insert(key).inserted else { continue }
            result.append(token)
        }
        return result
    }

    /// Deletes the tapped token and any duplicate copies of it — either sharing
    /// the same id or the same label+account. Users see duplicates as "the same
    /// token", so deleting one should remove them all.
    func removeCode(_ code: OTPCode) {
        let removed = codes.filter {
            $0.id == code.id || ($0.label == code.label && $0.account == code.account)
        }
        guard !removed.isEmpty else { return }

        codes.removeAll {
            $0.id == code.id || ($0.label == code.label && $0.account == code.account)
        }
        for token in removed {
            tombstones[token.id.uuidString] = Date()
        }
        saveCodes()
        persistTombstones()
        scheduleSync()
    }

    func updateCode(_ code: OTPCode, at index: Int) {
        guard codes.indices.contains(index) else { return }
        // Guarantee an edit is a *newer* write than what it replaces, even if a
        // caller handed back a copy that kept the old timestamp.
        codes[index] = code.modifiedAt > codes[index].modifiedAt ? code : code.edited()
        saveCodes()
        scheduleSync()
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

    private func performSync() async {
        guard isSyncEnabled else { return }
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
        apply(outcome)
    }

    /// Folds a merge result back into local storage.
    private func apply(_ outcome: SyncMergeOutcome) {
        if outcome.didAdoptRemoteChanges {
            // The sync snapshot was taken before this apply ran; a token added or
            // edited locally in the meantime is not in `outcome.tokens`. Preserve
            // those local changes instead of clobbering them with the older
            // snapshot (and giving SwiftUI an insert-then-delete diff).
            var merged = outcome.tokens
            let outcomeIDs = Set(outcome.tokens.map { $0.id })
            for local in codes where !outcomeIDs.contains(local.id) {
                merged.append(local)
            }
            codes = merged
        }
        tombstones = outcome.tombstones
        persistTombstones()
        saveCodes()
    }

    /// Awaits the sync so the caller can report an accurate background-fetch
    /// result to the system instead of claiming data it has not fetched yet.
    private func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) async -> Bool {
        guard syncService.handleRemoteNotification(userInfo: userInfo) else { return false }
        await syncNow()
        return true
    }

    private func loadSyncMetadata() {
        if let data = UserDefaults.standard.data(forKey: tombstonesKey),
           let decoded = try? JSONDecoder().decode([String: Date].self, from: data) {
            tombstones = decoded
        }
    }

    private func persistTombstones() {
        if let data = try? JSONEncoder().encode(tombstones) {
            UserDefaults.standard.set(data, forKey: tombstonesKey)
        }
    }

    // MARK: - Backup Functions

    /// Creates a backup file with current codes
    func createBackup() -> URL? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let backupName = "otp_backup_\(timestamp).json"
        let backupURL = backupDirectory.appendingPathComponent(backupName)

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(codes)
            try data.write(to: backupURL)
            return backupURL
        } catch {
            #if DEBUG
            print("Failed to create backup: \(error)")
            #endif
            return nil
        }
    }

    /// Creates a password-encrypted `.autheris` backup with current codes.
    func createEncryptedBackup(password: String) -> URL? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let backupName = "otp_backup_\(timestamp).autheris"
        let backupURL = backupDirectory.appendingPathComponent(backupName)

        do {
            let plaintext = try JSONEncoder().encode(codes)
            let encrypted = try BackupCrypto.encrypt(plaintext: plaintext, password: password)
            try encrypted.write(to: backupURL)
            return backupURL
        } catch {
            #if DEBUG
            print("Failed to create encrypted backup: \(error)")
            #endif
            return nil
        }
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

    /// Restores codes from a backup file. Pass the password for `.autheris`
    /// encrypted backups; plain `.json` backups ignore it.
    func restoreFromBackup(at url: URL, password: String? = nil) -> Bool {
        do {
            let fileData = try Data(contentsOf: url)
            let plaintext: Data
            if url.pathExtension.lowercased() == "autheris" {
                guard let password else { return false }
                plaintext = try BackupCrypto.decrypt(data: fileData, password: password)
            } else {
                plaintext = fileData
            }
            let restoredCodes = try JSONDecoder().decode([OTPCode].self, from: plaintext)
            // A restore replaces local state wholesale, so a token the backup does
            // not contain has effectively been deleted and must propagate as a
            // deletion rather than silently reappearing from iCloud later.
            let previousIDs = Set(codes.map { $0.id.uuidString })
            let restoredIDs = Set(restoredCodes.map { $0.id.uuidString })
            codes = restoredCodes
            for id in previousIDs.subtracting(restoredIDs) {
                tombstones[id] = Date()
            }
            for id in restoredIDs {
                tombstones.removeValue(forKey: id)
            }
            saveCodes()
            persistTombstones()
            scheduleSync()
            // Explicitly trigger UI update
            objectWillChange.send()
            return true
        } catch {
            #if DEBUG
            print("Failed to restore backup: \(error)")
            #endif
            return false
        }
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

    /// Imports data from JSON
    func importData(from data: Data) -> Bool {
        do {
            // First try to decode as ExportData (new format)
            if let exportData = try? JSONDecoder().decode(ExportData.self, from: data) {
                codes.append(contentsOf: exportData.tokens)
                saveCodes()
                scheduleSync()
                // Explicitly trigger UI update
                objectWillChange.send()
                return true
            }

            // Fall back to old format (array of OTPCode)
            let importedCodes = try JSONDecoder().decode([OTPCode].self, from: data)
            codes.append(contentsOf: importedCodes)
            saveCodes()
            scheduleSync()
            // Explicitly trigger UI update
            objectWillChange.send()
            return true
        } catch {
            #if DEBUG
            print("Failed to import data: \(error)")
            #endif
            return false
        }
    }
}

// MARK: - Export Data Structure

nonisolated struct ExportData: Codable, Sendable {
    let version: String
    let timestamp: Date
    let tokens: [OTPCode]
}
