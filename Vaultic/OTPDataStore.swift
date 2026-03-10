import Foundation
import Combine

class OTPDataStore: ObservableObject {
    @Published var codes: [OTPCode] = []
    private let saveKey = "otpCodes"
    private let backupDirectory: URL
    
    init() {
        // Create backup directory if it doesn't exist
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        backupDirectory = documentsDirectory.appendingPathComponent("OTPBackups")
        
        try? FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        
        loadCodes()
    }
    
    func saveCodes() {
        if let encoded = try? JSONEncoder().encode(codes) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
            // Force UI update by publishing changes
            objectWillChange.send()
        }
    }
    
    func loadCodes() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([OTPCode].self, from: data) {
            codes = decoded
            // Force UI update
            objectWillChange.send()
        } else {
            // Default sample codes with UNIQUE secrets for testing
            codes = [
                OTPCode(label: "GitHub", account: "hunter@dev.com", secret: "JBSWY3DPEHPK3PXPA"),
                OTPCode(label: "Google", account: "hunter.eddington", secret: "JBSWY3DPEHPK3PXPB"),
                OTPCode(label: "Work VPN", account: "h.eddington", secret: "JBSWY3DPEHPK3PXPC"),
                OTPCode(label: "AWS", account: "hunter@dev.com", secret: "JBSWY3DPEHPK3PXPD"),
                OTPCode(label: "Dropbox", account: "hunter", secret: "JBSWY3DPEHPK3PXPE")
            ]
            saveCodes()
        }
    }
    
    func addCode(_ code: OTPCode) {
        codes.append(code)
        saveCodes()
        // No need to manually trigger - @Published will do it automatically
    }
    
    func removeCode(at index: Int) {
        codes.remove(at: index)
        saveCodes()
    }
    
    func updateCode(_ code: OTPCode, at index: Int) {
        codes[index] = code
        saveCodes()
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
            print("Failed to create backup: \(error)")
            return nil
        }
    }
    
    /// Lists all available backup files
    func listBackups() -> [URL] {
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: backupDirectory, 
                                                                       includingPropertiesForKeys: [.creationDateKey],
                                                                       options: .skipsHiddenFiles)
            return fileURLs.filter { $0.pathExtension == "json" }
                .sorted { url1, url2 in
                    let date1 = try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate
                    let date2 = try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate
                    return (date1 ?? Date.distantPast) > (date2 ?? Date.distantPast)
                }
        } catch {
            print("Failed to list backups: \(error)")
            return []
        }
    }
    
    /// Restores codes from a backup file
    func restoreFromBackup(at url: URL) -> Bool {
        do {
            let data = try Data(contentsOf: url)
            let restoredCodes = try JSONDecoder().decode([OTPCode].self, from: data)
            codes = restoredCodes
            saveCodes()
            // Explicitly trigger UI update
            objectWillChange.send()
            return true
        } catch {
            print("Failed to restore backup: \(error)")
            return false
        }
    }
    
    /// Deletes a backup file
    func deleteBackup(at url: URL) -> Bool {
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            print("Failed to delete backup: \(error)")
            return false
        }
    }
    
    /// Creates JSON data for QR code export
    func exportData() -> Data? {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            
            // Create export structure with all tokens
            let exportData = ExportData(
                version: "1.0",
                timestamp: Date(),
                tokens: codes
            )
            
            return try encoder.encode(exportData)
        } catch {
            print("Failed to export data: \(error)")
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
                // Explicitly trigger UI update
                objectWillChange.send()
                return true
            }
            
            // Fall back to old format (array of OTPCode)
            let importedCodes = try JSONDecoder().decode([OTPCode].self, from: data)
            codes.append(contentsOf: importedCodes)
            saveCodes()
            // Explicitly trigger UI update
            objectWillChange.send()
            return true
        } catch {
            print("Failed to import data: \(error)")
            return false
        }
    }
}

// MARK: - Export Data Structure

struct ExportData: Codable {
    let version: String
    let timestamp: Date
    let tokens: [OTPCode]
}

