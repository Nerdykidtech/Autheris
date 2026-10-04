import Foundation

/// What the Transfer QR Code holds: an `autheris://import` link carrying codes.
///
/// There are two formats, and the smaller one that fits is used:
///
/// - **Version 1** is the full JSON export (`ExportData`), Base64-encoded. It is
///   what every release reads, so it is used whenever it fits in one QR code —
///   a device still on an older version can import it. It is large, though:
///   about 430 bytes a code, so a QR code holds only 8.
/// - **Version 2** (`v=2` in the link) is compact. It carries only what an import
///   keeps — label, account, secret, and any setting that isn't the default — and
///   it is compressed. Ids and dates are left out because an import gives every
///   code a new id and timestamp anyway (`OTPDataStore.addCodes`). About 55 bytes
///   a code, so a QR code holds around 75. It needs 2.9 or later to import.
///
/// Version 2, after compression, is binary:
///
///     format     1 byte, 2
///     count      varint
///     per code:
///       flags    1 byte, see `Flag`
///       label    string
///       account  string
///       secret   bytes (the Base32 secret decoded), or a string with `.textSecret`
///       then, each only if its flag is set:
///       algorithm 1 byte · digits 1 byte · period varint · counter varint ·
///       ring colour string
///
/// A string or byte run is a varint length followed by that many bytes (UTF-8 for
/// strings). Pure and `nonisolated` so it can be tested without the app.
nonisolated enum TransferPayload {

    /// The most a QR code holds: byte mode, version 40, error correction L — the
    /// level `QRCodeView` uses.
    static let maximumQRBytes = 2953

    /// The link for `codes`, or `nil` when even the compact format doesn't fit in
    /// one QR code.
    static func link(for codes: [OTPCode]) -> String? {
        if let legacy = legacyLink(for: codes), legacy.utf8.count <= maximumQRBytes {
            return legacy
        }
        guard let compact = compactLink(for: codes), compact.utf8.count <= maximumQRBytes else {
            return nil
        }
        return compact
    }

    /// The version 1 link, as every release has written it.
    static func legacyLink(for codes: [OTPCode]) -> String? {
        let export = ExportData(version: "1.0", timestamp: Date(), tokens: codes)
        guard let json = try? JSONEncoder().encode(export) else { return nil }
        return "autheris://import?data=\(base64URL(json))"
    }

    /// The version 2 link.
    static func compactLink(for codes: [OTPCode]) -> String? {
        guard let compressed = try? (encode(codes) as NSData).compressed(using: .zlib) else { return nil }
        return "autheris://import?v=2&data=\(base64URL(compressed as Data))"
    }

    /// The codes in a version 2 payload — the `data` item, Base64 decoded — or
    /// `nil` if it isn't one.
    ///
    /// The payload comes from a QR code or a link anyone can make, so every length
    /// is checked against what is left rather than trusted.
    static func decodeCompact(_ compressed: Data) -> [OTPCode]? {
        // A QR code's worth of input can't legitimately inflate past this, so a
        // payload that does is refused. The check comes after inflating, not
        // instead of it — `NSData` has no streaming limit — which is bounded by
        // the input cap above: DEFLATE expands at most about 1,032 to 1, so
        // 2,953 bytes can never become more than about 3 MB.
        guard compressed.count <= maximumQRBytes,
              let inflated = try? (compressed as NSData).decompressed(using: .zlib) as Data,
              inflated.count <= 1_000_000 else { return nil }
        return decode(inflated)
    }

    // MARK: - Binary

    private static let formatVersion: UInt8 = 2

    /// Which of a code's optional fields follow, and how its secret is held.
    private struct Flag: OptionSet {
        let rawValue: UInt8
        static let algorithm = Flag(rawValue: 1 << 0)
        static let digits = Flag(rawValue: 1 << 1)
        static let period = Flag(rawValue: 1 << 2)
        static let counterBased = Flag(rawValue: 1 << 3)
        static let counter = Flag(rawValue: 1 << 4)
        static let pinned = Flag(rawValue: 1 << 5)
        /// The secret is carried as text, because turning it into bytes and back
        /// would not give the same text — lowercase, spaces, padding, or a
        /// character outside Base32. Rare, but the code must arrive as it left.
        static let textSecret = Flag(rawValue: 1 << 6)
        static let ringColor = Flag(rawValue: 1 << 7)
    }

    private static let algorithms: [OTPAlgorithm] = [.sha1, .sha256, .sha512]

    static func encode(_ codes: [OTPCode]) -> Data {
        var out = Data([formatVersion])
        appendVarint(UInt64(codes.count), to: &out)
        for code in codes {
            let secretBytes = OTPGenerator.decodeBase32(code.secret)
            let secretIsCanonical = OTPGenerator.encodeBase32(secretBytes) == code.secret

            var flags: Flag = []
            if code.algorithm != .sha1 { flags.insert(.algorithm) }
            if code.digits != 6 { flags.insert(.digits) }
            if code.period != 30 { flags.insert(.period) }
            if code.kind == .hotp { flags.insert(.counterBased) }
            if code.counter != 0 { flags.insert(.counter) }
            if code.isPinned { flags.insert(.pinned) }
            if !secretIsCanonical { flags.insert(.textSecret) }
            if code.timerRingHex != nil { flags.insert(.ringColor) }

            out.append(flags.rawValue)
            appendBytes(Data(code.label.utf8), to: &out)
            appendBytes(Data(code.account.utf8), to: &out)
            appendBytes(secretIsCanonical ? secretBytes : Data(code.secret.utf8), to: &out)
            if flags.contains(.algorithm) {
                out.append(UInt8(algorithms.firstIndex(of: code.algorithm) ?? 0))
            }
            if flags.contains(.digits) { out.append(UInt8(clamping: code.digits)) }
            if flags.contains(.period) { appendVarint(UInt64(max(0, code.period)), to: &out) }
            if flags.contains(.counter) { appendVarint(code.counter, to: &out) }
            if let ring = code.timerRingHex { appendBytes(Data(ring.utf8), to: &out) }
        }
        return out
    }

    static func decode(_ data: Data) -> [OTPCode]? {
        var reader = Reader(bytes: [UInt8](data))
        guard reader.byte() == formatVersion, let count = reader.varint(),
              // Each code takes at least four bytes, so a count beyond that is a lie.
              count <= UInt64(reader.remaining / 4) else { return nil }

        var codes: [OTPCode] = []
        for _ in 0..<count {
            guard let rawFlags = reader.byte(),
                  let label = reader.string(),
                  let account = reader.string(),
                  let secretField = reader.field() else { return nil }
            let flags = Flag(rawValue: rawFlags)

            let secret: String
            if flags.contains(.textSecret) {
                guard let text = String(data: secretField, encoding: .utf8) else { return nil }
                secret = text
            } else {
                secret = OTPGenerator.encodeBase32(secretField)
            }

            var algorithm = OTPAlgorithm.sha1
            if flags.contains(.algorithm) {
                guard let index = reader.byte(), Int(index) < algorithms.count else { return nil }
                algorithm = algorithms[Int(index)]
            }
            var digits = 6
            if flags.contains(.digits) {
                guard let value = reader.byte() else { return nil }
                digits = Int(value)
            }
            var period = 30
            if flags.contains(.period) {
                guard let value = reader.varint(), value <= UInt64(Int32.max) else { return nil }
                period = Int(value)
            }
            var counter: UInt64 = 0
            if flags.contains(.counter) {
                guard let value = reader.varint() else { return nil }
                // Clamped for the same reason every other way in clamps it: the
                // iCloud record can't carry more back.
                counter = min(value, OTPCode.maximumCounter)
            }
            var ring: String?
            if flags.contains(.ringColor) {
                guard let value = reader.string() else { return nil }
                ring = value
            }

            codes.append(OTPCode(label: label, account: account, secret: secret,
                                 algorithm: algorithm, digits: digits, period: period,
                                 kind: flags.contains(.counterBased) ? .hotp : .totp,
                                 counter: counter, timerRingHex: ring,
                                 isPinned: flags.contains(.pinned)))
        }
        // Anything left over means this isn't the format it claimed to be.
        return reader.remaining == 0 ? codes : nil
    }

    // MARK: - Helpers

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func appendVarint(_ value: UInt64, to out: inout Data) {
        var value = value
        repeat {
            var byte = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 { byte |= 0x80 }
            out.append(byte)
        } while value != 0
    }

    private static func appendBytes(_ bytes: Data, to out: inout Data) {
        appendVarint(UInt64(bytes.count), to: &out)
        out.append(bytes)
    }

    /// Reads the binary format front to back, returning `nil` for anything that
    /// would run past the end.
    private struct Reader {
        let bytes: [UInt8]
        var offset = 0

        var remaining: Int { bytes.count - offset }

        mutating func byte() -> UInt8? {
            guard offset < bytes.count else { return nil }
            defer { offset += 1 }
            return bytes[offset]
        }

        mutating func varint() -> UInt64? {
            var value: UInt64 = 0
            for shift in stride(from: 0, to: 64, by: 7) {
                guard let byte = byte() else { return nil }
                value |= UInt64(byte & 0x7F) << UInt64(shift)
                if byte & 0x80 == 0 { return value }
            }
            return nil
        }

        mutating func field() -> Data? {
            guard let length = varint(), length <= UInt64(remaining) else { return nil }
            defer { offset += Int(length) }
            return Data(bytes[offset..<offset + Int(length)])
        }

        mutating func string() -> String? {
            field().flatMap { String(data: $0, encoding: .utf8) }
        }
    }
}
