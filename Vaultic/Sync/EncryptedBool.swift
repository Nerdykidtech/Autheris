import Foundation

/// How a `Bool` is written into and read out of a CloudKit **encrypted** field.
///
/// `isPinned` is stored as `"1"` / `"0"` rather than as an `NSNumber`, matching
/// every other encrypted field in this schema — `label`, `account`, `secret` and
/// `timerRingHex` are all Strings, while every numeric field (`deleted`,
/// `digits`, `period`) is a plain one. That is the one shape already proven to
/// work end to end against the production container, and CloudKit will not let a
/// field change type once it exists, so matching it is not a style preference:
/// it is the difference between a path that has been exercised for real and one
/// that has not.
///
/// Reading is deliberately lenient. A missing key, a field of an unexpected type,
/// or a hand-edited Console value all have to read as "not pinned" rather than
/// failing the record — `CloudKitTokenSyncService.decode` skips a record it
/// cannot interpret, which to the user looks like sync silently dropping tokens.
nonisolated enum EncryptedBool {

    /// The stored form. Emphatically not a number; see the note above.
    static func text(_ value: Bool) -> String { value ? "1" : "0" }

    /// Reads any form the field might plausibly hold.
    static func value(_ raw: Any?) -> Bool {
        if let text = raw as? String {
            return text == "1" || text.caseInsensitiveCompare("true") == .orderedSame
        }
        // Tolerated so a development container that created the field as an
        // integer does not silently read every pin back as `false`.
        if let number = raw as? NSNumber {
            return number.boolValue
        }
        return false
    }
}
