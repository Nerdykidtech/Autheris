import XCTest
@testable import Vaultic

/// The phone↔watch contract, asserted on both sides of it.
///
/// `WatchTokenPayload` is the only thing the iPhone app and the watch app have to
/// agree on, and the two run as separate binaries that can be at different
/// versions — so the cases that matter are the ones where they *disagree*: an
/// unknown version, a payload that arrives out of order, an empty list. All of
/// them are pure, so none needs a paired watch.
final class WatchTokenPayloadTests: XCTestCase {

    private func token(
        label: String = "GitHub",
        account: String = "octocat",
        secret: String = "JBSWY3DPEHPK3PXP",
        algorithm: OTPAlgorithm = .sha1,
        digits: Int = 6,
        period: Int = 30,
        kind: OTPKind = .totp,
        counter: UInt64 = 0,
        timerRingHex: String? = nil,
        isPinned: Bool = false,
        modifiedAt: Date = Date()
    ) -> OTPCode {
        OTPCode(label: label, account: account, secret: secret,
                algorithm: algorithm, digits: digits, period: period,
                kind: kind, counter: counter,
                timerRingHex: timerRingHex, isPinned: isPinned, modifiedAt: modifiedAt)
    }

    // MARK: - Round trip

    func testTokensSurviveARoundTripUnchanged() throws {
        let tokens = [
            token(),
            token(label: "AWS", account: "root", secret: "GEZDGNBVGY3TQOJQ",
                  algorithm: .sha256, digits: 8, period: 60,
                  timerRingHex: "FF9900", isPinned: true),
            // A counter-based code has to cross the wire with its counter intact:
            // the same counter is what makes the watch's code and the phone's the
            // same code.
            token(label: "Counter", secret: "GEZDGNBVGY3TQOJQ", kind: .hotp, counter: 12),
        ]

        let blob = try WatchTokenPayload.encode(tokens, sentAt: Date(timeIntervalSince1970: 1_700_000_000))
        let decoded = try XCTUnwrap(WatchTokenPayload.decode(blob))

        XCTAssertEqual(decoded.tokens, tokens)
        XCTAssertEqual(decoded.sentAt, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(decoded.tokens.last?.kind, .hotp)
        XCTAssertEqual(decoded.tokens.last?.counter, 12)
    }

    /// The version is not decoration: it is what stops an older watch from rendering
    /// a payload it cannot honour.
    ///
    /// A counter-based token decodes happily in a build that has never heard of one —
    /// `OTPCode`'s decoder tolerates the missing keys and defaults to time-based — so
    /// without a version bump that watch would show a plausible code that the service
    /// rejects. Ignoring the whole payload instead leaves it showing the list it
    /// already had, which is out of date rather than wrong.
    func testThePayloadVersionIsWhatMakesAnOlderWatchRefuseTheCounter() {
        XCTAssertEqual(WatchTokenPayload.version, 2)
    }

    /// The watch shows the codes in the order it receives them and has no
    /// reordering UI of its own, so the *array order* is the interface. Losing it
    /// would silently reshuffle what the user sees.
    func testOrderIsPreserved() throws {
        let tokens = [token(label: "First"), token(label: "Second"), token(label: "Third")]
        let decoded = try XCTUnwrap(WatchTokenPayload.decode(try WatchTokenPayload.encode(tokens)))
        XCTAssertEqual(decoded.tokens.map(\.label), ["First", "Second", "Third"])
    }

    /// A phone with no codes has to be able to say so — otherwise the watch sits
    /// on "waiting for iPhone" forever after the user deletes their last code.
    func testAnEmptyListIsAPayloadNotAnAbsence() throws {
        let decoded = try XCTUnwrap(WatchTokenPayload.decode(try WatchTokenPayload.encode([])))
        XCTAssertEqual(decoded.tokens, [])
    }

    // MARK: - The application context

    func testApplicationContextCarriesThePayload() throws {
        let tokens = [token()]
        let context = try XCTUnwrap(WatchTokenPayload.applicationContext(for: tokens))
        let decoded = try XCTUnwrap(WatchTokenPayload.decode(applicationContext: context))
        XCTAssertEqual(decoded.tokens, tokens)
    }

    func testAnUnknownVersionIsIgnoredRatherThanRead() throws {
        // Exactly the shape a future build would send, with the version field
        // moved past what this build knows.
        let future = """
        {"version": 99, "sentAt": 0, "tokens": [{"id":"\(UUID().uuidString)","label":"GitHub","account":"octocat","secret":"JBSWY3DPEHPK3PXP"}]}
        """
        XCTAssertNil(WatchTokenPayload.decode(Data(future.utf8)))
        XCTAssertNil(WatchTokenPayload.decode(applicationContext: [WatchTokenPayload.tokensKey: Data(future.utf8)]))
    }

    func testGarbageIsIgnoredRatherThanRead() {
        XCTAssertNil(WatchTokenPayload.decode(Data("not json".utf8)))
        XCTAssertNil(WatchTokenPayload.decode(Data()))
    }

    /// A context carrying every other key the app uses, but not the token blob.
    func testAContextWithoutTokensDecodesToNil() {
        XCTAssertNil(WatchTokenPayload.decode(applicationContext: ["somethingElse": 1]))
    }

    // MARK: - The context size ceiling

    /// Past the ceiling the caller must be told to take the file route, rather
    /// than hand `WCSession` a dictionary it will reject.
    func testAnOversizedListDoesNotProduceAContext() {
        // Padding the labels guarantees the encoded blob passes the budget no
        // matter how much a token's other fields shrink.
        let filler = String(repeating: "x", count: WatchTokenPayload.maximumContextBytes)
        XCTAssertNil(WatchTokenPayload.applicationContext(for: [token(label: filler, account: filler)]))
    }

    func testAnOrdinaryListIsWellInsideTheCeiling() throws {
        let tokens = (0..<50).map { token(label: "Issuer \($0)", account: "user-\($0)@example.com") }
        XCTAssertNotNil(WatchTokenPayload.applicationContext(for: tokens))
    }

    // MARK: - Out-of-order delivery

    /// The relay has two transports — an application context and, for oversized
    /// lists, a file — and nothing orders the two. The stamp on the payload is
    /// what stops the watch being rolled back to an older list by one arriving
    /// after the other.
    func testAnOlderPayloadDoesNotReplaceANewerOne() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = WatchTokenPayload.Decoded(sentAt: now, tokens: [token(label: "New")])
        let older = WatchTokenPayload.Decoded(sentAt: now.addingTimeInterval(-60), tokens: [token(label: "Old")])

        XCTAssertFalse(WatchTokenPayload.isNewer(older, than: now))
        XCTAssertTrue(WatchTokenPayload.isNewer(newer, than: now))
    }

    /// A watch that has never received anything has an "applied at" of
    /// `.distantPast`, so the very first payload — whatever its stamp — is taken.
    func testTheFirstPayloadIsAlwaysAccepted() {
        let decoded = WatchTokenPayload.Decoded(sentAt: .distantPast, tokens: [])
        XCTAssertTrue(WatchTokenPayload.isNewer(decoded, than: .distantPast))
    }
}
