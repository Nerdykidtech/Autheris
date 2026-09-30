import XCTest
@testable import Vaultic

/// `OTPCode` keeps a hand-written `init(from:)` so that tokens persisted before
/// iCloud Sync existed still decode. If that decoder ever grows a strict
/// `decode` for one of the newer fields, every existing user's vault fails to
/// load — so the backward-compatibility cases below are load-bearing.
final class OTPCodeCodableTests: XCTestCase {

    /// The shape written before sync existed: only the four original fields, and
    /// no `modifiedAt`.
    private let preSyncJSON = """
    {
      "id": "3F2504E0-4F89-11D3-9A0C-0305E82C3301",
      "label": "GitHub",
      "account": "octocat",
      "secret": "JBSWY3DPEHPK3PXP"
    }
    """

    func testDecodesPreSyncJSONAndDefaultsEveryMissingField() throws {
        let decoded = try JSONDecoder().decode(OTPCode.self, from: Data(preSyncJSON.utf8))

        XCTAssertEqual(decoded.id, UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301"))
        XCTAssertEqual(decoded.label, "GitHub")
        XCTAssertEqual(decoded.account, "octocat")
        XCTAssertEqual(decoded.secret, "JBSWY3DPEHPK3PXP")
        XCTAssertEqual(decoded.algorithm, .sha1)
        XCTAssertEqual(decoded.digits, 6)
        XCTAssertEqual(decoded.period, 30)
        // Added when counter-based codes arrived, long after this shape was
        // written, so these have to default too.
        XCTAssertEqual(decoded.kind, .totp)
        XCTAssertEqual(decoded.counter, 0)
        XCTAssertNil(decoded.timerRingHex)
        // Added long after the first release, so it has to default rather than
        // make an existing vault unreadable.
        XCTAssertFalse(decoded.isPinned)
        // A token with no `modifiedAt` has to lose to any genuinely edited copy.
        XCTAssertEqual(decoded.modifiedAt, .distantPast)
    }

    func testDecodedPreSyncTokenLosesToADatedRemoteEdit() throws {
        let decoded = try JSONDecoder().decode(OTPCode.self, from: Data(preSyncJSON.utf8))
        let remote = OTPCode(id: decoded.id,
                             label: "Renamed",
                             account: decoded.account,
                             secret: decoded.secret,
                             modifiedAt: Date(timeIntervalSince1970: 1_700_000_000))

        let outcome = SyncMergeEngine.merge(
            local: SyncLocalState(tokens: [decoded]),
            remote: [.live(remote)],
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertEqual(outcome.tokens.map(\.label), ["Renamed"])
        XCTAssertTrue(outcome.uploads.isEmpty)
    }

    func testRoundTripPreservesEveryField() throws {
        let original = OTPCode(label: "Example",
                               account: "user@example.com",
                               secret: "JBSWY3DPEHPK3PXP",
                               algorithm: .sha256,
                               digits: 8,
                               period: 60,
                               kind: .hotp,
                               counter: 7,
                               timerRingHex: "FF8800",
                               isPinned: true,
                               modifiedAt: Date(timeIntervalSince1970: 1_700_000_000))

        let decoded = try JSONDecoder().decode(OTPCode.self, from: JSONEncoder().encode(original))

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.label, original.label)
        XCTAssertEqual(decoded.account, original.account)
        XCTAssertEqual(decoded.secret, original.secret)
        XCTAssertEqual(decoded.algorithm, original.algorithm)
        XCTAssertEqual(decoded.digits, original.digits)
        XCTAssertEqual(decoded.period, original.period)
        XCTAssertEqual(decoded.kind, original.kind)
        XCTAssertEqual(decoded.counter, original.counter)
        XCTAssertEqual(decoded.timerRingHex, original.timerRingHex)
        XCTAssertEqual(decoded.isPinned, original.isPinned)
        XCTAssertEqual(decoded.modifiedAt.timeIntervalSince1970,
                       original.modifiedAt.timeIntervalSince1970,
                       accuracy: 0.001)
    }

    func testATokenMissingItsSecretIsRejected() throws {
        // `secret` is the one field with no default; it must stay required so a
        // malformed row fails loudly rather than producing an unusable token.
        let json = """
        { "id": "3F2504E0-4F89-11D3-9A0C-0305E82C3301", "label": "L", "account": "a" }
        """
        XCTAssertThrowsError(try JSONDecoder().decode(OTPCode.self, from: Data(json.utf8)))
    }

    // MARK: - Optional account

    func testAnEmptyAccountIsAValidRoundTrippableState() throws {
        // Account is optional by design: the add form allows it to be left blank and
        // the edit form has always allowed it to be cleared. Making it required —
        // here or in `isFormValid` — would break every token that has no account, so
        // this pins it as a supported state rather than an accident.
        let token = OTPCode(label: "GitHub", account: "",
                            secret: "JBSWY3DPEHPK3PXP",
                            modifiedAt: Date(timeIntervalSince1970: 1_000_000))

        let decoded = try JSONDecoder().decode(OTPCode.self, from: JSONEncoder().encode(token))

        XCTAssertEqual(decoded.account, "")
        XCTAssertEqual(decoded, token)
        // And it still produces a code.
        XCTAssertEqual(decoded.currentCode.count, 6)
    }

    // MARK: - edited()

    func testEditedBumpsTheTimestampAndPreservesIdentity() {
        let before = Date(timeIntervalSince1970: 1_000_000)
        let after = Date(timeIntervalSince1970: 2_000_000)
        let original = OTPCode(label: "Before", account: "octocat",
                               secret: "JBSWY3DPEHPK3PXP", modifiedAt: before)

        let edited = original.edited(label: "After", modifiedAt: after)

        XCTAssertEqual(edited.id, original.id)
        XCTAssertEqual(edited.label, "After")
        XCTAssertEqual(edited.modifiedAt, after)
        // Fields the caller did not touch survive the edit untouched.
        XCTAssertEqual(edited.account, original.account)
        XCTAssertEqual(edited.secret, original.secret)
        XCTAssertEqual(edited.algorithm, original.algorithm)
        XCTAssertEqual(edited.digits, original.digits)
        XCTAssertEqual(edited.period, original.period)
        XCTAssertEqual(edited.timerRingHex, original.timerRingHex)
    }

    func testEditedCanPinAndUnpinWithoutTouchingAnythingElse() {
        let before = Date(timeIntervalSince1970: 1_000_000)
        let after = Date(timeIntervalSince1970: 2_000_000)
        let original = OTPCode(label: "L", account: "a", secret: "JBSWY3DPEHPK3PXP",
                               isPinned: false, modifiedAt: before)

        let pinned = original.edited(isPinned: true, modifiedAt: after)
        let unpinned = pinned.edited(isPinned: false, modifiedAt: after)

        XCTAssertTrue(pinned.isPinned)
        XCTAssertFalse(unpinned.isPinned)
        // A pin is an edit like any other: it has to carry a newer timestamp, or
        // sync would not see it as a change worth propagating.
        XCTAssertEqual(pinned.modifiedAt, after)
        XCTAssertEqual(pinned.id, original.id)
        XCTAssertEqual(pinned.label, original.label)
        XCTAssertEqual(pinned.secret, original.secret)
    }

    func testAnUnrelatedEditKeepsThePin() {        // Guards the whole class of bug the edit screens had: rebuilding a token by
        // hand dropped any field the screen did not know about, which would have
        // silently unpinned a code the moment its label or secret was changed.
        let pinned = OTPCode(label: "L", account: "a",
                             secret: "JBSWY3DPEHPK3PXP", isPinned: true)

        XCTAssertTrue(pinned.edited(label: "Renamed").isPinned)
        XCTAssertTrue(pinned.edited(account: "other@example.com").isPinned)
        XCTAssertTrue(pinned.edited(secret: "KRSXG5CTMVRXEZLU").isPinned)
        XCTAssertTrue(pinned.edited(timerRingHex: .some("FF8800")).isPinned)
        XCTAssertTrue(pinned.edited(algorithm: .sha512, digits: 8, period: 60).isPinned)
    }

    func testEditedDefaultsToNowSoAnEditAlwaysBeatsTheCopyItReplaces() {
        let original = OTPCode(label: "Before", account: "octocat",
                               secret: "JBSWY3DPEHPK3PXP",
                               modifiedAt: Date(timeIntervalSince1970: 1_000_000))

        XCTAssertGreaterThan(original.edited().modifiedAt, original.modifiedAt)
    }

    func testEditingTheAlgorithmKeepsEverythingElse() {
        // The repair path for a token created with the wrong algorithm — which is
        // how a service like myGov ends up showing codes that get rejected. Editing
        // it has to change the algorithm and nothing else.
        let original = OTPCode(label: "myGov", account: "me",
                               secret: "JBSWY3DPEHPK3PXP",
                               algorithm: .sha1, digits: 6, period: 30,
                               modifiedAt: Date(timeIntervalSince1970: 1_000_000))

        let repaired = original.edited(algorithm: .sha256,
                                       modifiedAt: Date(timeIntervalSince1970: 2_000_000))

        XCTAssertEqual(repaired.algorithm, .sha256)
        XCTAssertEqual(repaired.id, original.id)
        XCTAssertEqual(repaired.label, original.label)
        XCTAssertEqual(repaired.account, original.account)
        XCTAssertEqual(repaired.secret, original.secret)
        XCTAssertEqual(repaired.digits, original.digits)
        XCTAssertEqual(repaired.period, original.period)
        XCTAssertEqual(repaired.modifiedAt, Date(timeIntervalSince1970: 2_000_000))
    }

    func testATokenWithAMalformedPeriodStillYieldsAUsableCode() {
        // A period of zero reaches `OTPCode` from an `otpauth://` URL or a foreign
        // backup, and used to trap on every launch once it had been saved.
        let broken = OTPCode(label: "Broken", account: "a",
                             secret: "JBSWY3DPEHPK3PXP",
                             digits: 6, period: 0)

        XCTAssertEqual(broken.effectivePeriod, 30)
        XCTAssertEqual(broken.currentCode.count, 6)
        // The countdown ring reads `effectivePeriod`, so it cannot disagree with the
        // code it is counting down for.
        XCTAssertEqual(broken.effectivePeriod, OTPGenerator.effectivePeriod(broken.period))
    }

    func testEditedCanClearTheTimerRingColour() {
        let original = OTPCode(label: "L", account: "a", secret: "JBSWY3DPEHPK3PXP",
                               timerRingHex: "FF8800")

        // `timerRingHex` is a double optional so `nil` can mean "revert to the
        // issuer's automatic colour" rather than "leave it alone".
        XCTAssertEqual(original.edited(timerRingHex: .some(nil)).timerRingHex, nil)
        XCTAssertEqual(original.edited().timerRingHex, "FF8800")
    }

    // MARK: - Counter-based tokens

    func testACounterBasedCodeIsTheCodeForItsCounterAndNotTheClock() {
        // The whole point of the kind: the two generate from the same secret and the
        // same construction, and differ only in what the counter is derived from. If
        // a counter-based token were ever rendered through the time-based path, its
        // codes would be plausible and wrong.
        let secret = "JBSWY3DPEHPK3PXP"
        let token = OTPCode(label: "L", account: "a", secret: secret,
                            kind: .hotp, counter: 4)

        XCTAssertEqual(token.currentCode, OTPGenerator.generateHOTP(secret: secret, counter: 4))
        XCTAssertNotEqual(token.currentCode, OTPGenerator.generateOTP(secret: secret))
    }

    func testAdvancingTheCounterChangesTheCodeAndKeepsEverythingElse() {
        let secret = "JBSWY3DPEHPK3PXP"
        let token = OTPCode(label: "L", account: "a", secret: secret,
                            kind: .hotp, counter: 0)

        let next = token.edited(counter: 1)

        XCTAssertNotEqual(token.currentCode, next.currentCode)
        XCTAssertEqual(next.currentCode, OTPGenerator.generateHOTP(secret: secret, counter: 1))
        XCTAssertEqual(next.id, token.id)
        XCTAssertEqual(next.kind, .hotp)
        XCTAssertEqual(next.counter, 1)
    }

    func testAnUnrelatedEditKeepsTheKindAndCounter() {
        // The same class of bug as the pin case above, and the more damaging one: a
        // code that lost its counter would start generating time-based codes that
        // the service rejects, and nothing on screen would look wrong.
        let counter = OTPCode(label: "L", account: "a", secret: "JBSWY3DPEHPK3PXP",
                              kind: .hotp, counter: 12)

        XCTAssertEqual(counter.edited(label: "Renamed").kind, .hotp)
        XCTAssertEqual(counter.edited(label: "Renamed").counter, 12)
        XCTAssertEqual(counter.edited(timerRingHex: .some("FF8800")).counter, 12)
        XCTAssertEqual(counter.edited(algorithm: .sha256, digits: 8).counter, 12)
    }

    func testAnUnrecognisedKindReadsAsTimeBasedRatherThanFailingTheDecode() throws {
        // A value written by a newer build, or a hand-edited backup. `kind` is
        // deliberately outside the strict part of the decoder: one field it cannot
        // read must not cost the user every token in the file.
        let json = """
        {
          "id": "3F2504E0-4F89-11D3-9A0C-0305E82C3301",
          "label": "L", "account": "a", "secret": "JBSWY3DPEHPK3PXP",
          "kind": "SOMETHING_NEW"
        }
        """

        let decoded = try JSONDecoder().decode(OTPCode.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.kind, .totp)
    }

    func testACounterBeyondWhatICloudCanCarryIsClamped() throws {
        // The counter is stored in a CloudKit `Int64` field, so a larger value would
        // be written as one number and read back as another — a wrong code with
        // nothing to notice it. The clamp is in the initialiser and in the decoder,
        // so it cannot be bypassed by a file.
        let tooBig = OTPCode(label: "L", account: "a", secret: "JBSWY3DPEHPK3PXP",
                             kind: .hotp, counter: UInt64.max)

        XCTAssertEqual(tooBig.counter, OTPCode.maximumCounter)
        XCTAssertEqual(OTPCode.maximumCounter, UInt64(Int64.max))

        let json = """
        {
          "id": "3F2504E0-4F89-11D3-9A0C-0305E82C3301",
          "label": "L", "account": "a", "secret": "JBSWY3DPEHPK3PXP",
          "kind": "HOTP", "counter": 18446744073709551615
        }
        """
        let decoded = try JSONDecoder().decode(OTPCode.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.counter, OTPCode.maximumCounter)
    }
}
