import Foundation

/// Whether a token's code comes from the clock or from a counter.
///
/// Both kinds are the same HMAC construction with a different counter —
/// `OTPGenerator` is where that lives — but they differ in everything the user
/// sees. A time-based code expires on its own and is replaced by the next one; a
/// counter-based code never expires, and is spent by *use*, which is why the
/// counter is a property of the token (`OTPCode.counter`) and has to persist,
/// sync and survive a restore. Getting that wrong is the difference between a code
/// that works and a code that is silently wrong, so the two are told apart by the
/// model rather than by how a view chooses to render them.
///
/// The raw values are what an `otpauth://` URL's host and the CloudKit `kind`
/// field carry, so they are stable and are asserted by a test.
nonisolated enum OTPKind: String, Codable, CaseIterable, Sendable {

    /// Time-based (RFC 6238). What nearly every service uses: the code is derived
    /// from the current time and the shared secret.
    case totp = "TOTP"

    /// Counter-based (RFC 4226). The code is derived from a counter the user
    /// advances, and it stays valid until the service says otherwise.
    case hotp = "HOTP"

    /// What an `otpauth://` URL's host means.
    ///
    /// The host is the only place the kind is stated in a setup URL — `totp` and
    /// `hotp` — and RFC 6238's own examples default to the time-based one when a
    /// URL names neither, so anything unrecognised means `.totp` rather than a
    /// refusal. A URL that says `hotp` is the one case that must *not* fall back:
    /// reading it as time-based is what produced wrong codes before this existed.
    init(urlHost: String?) {
        self = (urlHost?.lowercased() == "hotp") ? .hotp : .totp
    }
}
