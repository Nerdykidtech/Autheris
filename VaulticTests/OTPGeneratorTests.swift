import XCTest
@testable import Vaultic

/// The TOTP implementation checked against the published test vectors rather than
/// against itself. RFC 6238 Appendix B gives expected codes for SHA1, SHA256 and
/// SHA512 at fixed instants; RFC 4226 Appendix D gives the six-digit HOTP values
/// the first of those builds on. Together they pin the HMAC choice, the dynamic
/// truncation, the counter derivation and the zero-padding.
///
/// The reference secrets in the RFCs are ASCII. The app takes Base32, so they are
/// encoded here exactly the way an imported secret is (`encodeBase32`), which also
/// means these cases exercise that encoder.
final class OTPGeneratorTests: XCTestCase {

    private func base32Secret(_ ascii: String) -> String {
        OTPGenerator.encodeBase32(Data(ascii.utf8))
    }

    // RFC 6238 Appendix B's three secrets.
    private var sha1Secret: String { base32Secret("12345678901234567890") }
    private var sha256Secret: String { base32Secret("12345678901234567890123456789012") }
    private var sha512Secret: String {
        base32Secret("1234567890123456789012345678901234567890123456789012345678901234")
    }

    private func code(_ secret: String, _ algorithm: OTPAlgorithm, at seconds: TimeInterval) -> String {
        OTPGenerator.generateOTP(secret: secret,
                                 algorithm: algorithm,
                                 digits: 8,
                                 period: 30,
                                 now: Date(timeIntervalSince1970: seconds))
    }

    // MARK: - RFC 6238 Appendix B

    func testSHA1ReferenceVectors() {
        let expected: [(TimeInterval, String)] = [
            (59, "94287082"),
            (1_111_111_109, "07081804"),   // leading zero, so this also pins the padding
            (1_111_111_111, "14050471"),
            (1_234_567_890, "89005924"),
            (2_000_000_000, "69279037"),
            (20_000_000_000, "65353130"),
        ]

        for (seconds, value) in expected {
            XCTAssertEqual(code(sha1Secret, .sha1, at: seconds), value,
                           "SHA1 mismatch at T=\(seconds)")
        }
    }

    func testSHA256ReferenceVectors() {
        let expected: [(TimeInterval, String)] = [
            (59, "46119246"),
            (1_111_111_109, "68084774"),
            (1_111_111_111, "67062674"),
            (1_234_567_890, "91819424"),
            (2_000_000_000, "90698825"),
            (20_000_000_000, "77737706"),
        ]

        for (seconds, value) in expected {
            XCTAssertEqual(code(sha256Secret, .sha256, at: seconds), value,
                           "SHA256 mismatch at T=\(seconds)")
        }
    }

    func testSHA512ReferenceVectors() {
        let expected: [(TimeInterval, String)] = [
            (59, "90693936"),
            (1_111_111_109, "25091201"),
            (1_111_111_111, "99943326"),
            (1_234_567_890, "93441116"),
            (2_000_000_000, "38618901"),
            (20_000_000_000, "47863826"),
        ]

        for (seconds, value) in expected {
            XCTAssertEqual(code(sha512Secret, .sha512, at: seconds), value,
                           "SHA512 mismatch at T=\(seconds)")
        }
    }

    /// The three algorithms must actually differ — a dispatch bug that fell through
    /// to one primitive would otherwise pass every vector above for that primitive.
    func testTheThreeAlgorithmsProduceDifferentCodesForTheSameInstant() {
        let at = TimeInterval(59)
        let codes = Set([
            code(sha1Secret, .sha1, at: at),
            code(sha256Secret, .sha256, at: at),
            code(sha512Secret, .sha512, at: at),
        ])

        XCTAssertEqual(codes.count, 3)
    }

    // MARK: - RFC 4226 Appendix D (six digits, the app's default)

    func testSixDigitCountersMatchRFC4226() {
        // `period: 30` makes counter N correspond to `now` in [30N, 30N + 30).
        let expected: [(TimeInterval, String)] = [(0, "755224"), (30, "287082"), (60, "359152")]

        for (seconds, value) in expected {
            XCTAssertEqual(
                OTPGenerator.generateOTP(secret: sha1Secret, algorithm: .sha1, digits: 6,
                                         period: 30, now: Date(timeIntervalSince1970: seconds)),
                value,
                "six-digit mismatch at counter \(Int(seconds / 30))"
            )
        }
    }

    // MARK: - RFC 4226 Appendix D, through `generateHOTP`

    func testCounterBasedCountersMatchRFC4226() {
        // The same table as above, read through the counter-based entry point rather
        // than derived from a clock — which is the only difference between the two,
        // and the reason the values have to agree.
        let expected: [(UInt64, String)] = [
            (0, "755224"), (1, "287082"), (2, "359152"), (3, "969429"), (4, "338314"),
            (5, "254676"), (6, "287922"), (7, "162583"), (8, "399871"), (9, "520489")
        ]

        for (counter, value) in expected {
            XCTAssertEqual(
                OTPGenerator.generateHOTP(secret: sha1Secret, algorithm: .sha1,
                                          digits: 6, counter: counter),
                value,
                "counter \(counter)"
            )
        }
    }

    func testACounterBasedCodeIsTheTimeBasedCodeForThatSameCounter() {
        // The two kinds are one construction. This pins the seam: a time-based code
        // for the instant that falls in counter N's window must equal the
        // counter-based code for N, for every algorithm and every digit count. If the
        // counter derivation is ever changed on one side only, this fails.
        for period in [15, 30, 60] {
            for counter in 0...3 {
                let now = Date(timeIntervalSince1970: Double(counter) * Double(period) + 1)

                for algorithm in OTPAlgorithm.allCases {
                    for digits in [6, 8] {
                        XCTAssertEqual(
                            OTPGenerator.generateHOTP(secret: sha1Secret, algorithm: algorithm,
                                                      digits: digits, counter: UInt64(counter)),
                            OTPGenerator.generateOTP(secret: sha1Secret, algorithm: algorithm,
                                                     digits: digits, period: period, now: now),
                            "algorithm \(algorithm.rawValue), digits \(digits), counter \(counter), period \(period)"
                        )
                    }
                }
            }
        }
    }

    func testCounterBasedCodesDoNotDependOnTheClock() {
        // What distinguishes the two kinds for the user: a counter-based code is not
        // a snapshot of a moment, so the same counter yields the same code forever.
        // RFC 4226's own vector for counter 0 is the oldest value in either appendix.
        XCTAssertEqual(OTPGenerator.generateHOTP(secret: sha1Secret, digits: 6, counter: 0), "755224")
    }

    func testTheLargestCounterStillProducesACode() {
        // `OTPCode.maximumCounter` allows a counter up to `Int64.max` — the ceiling
        // the iCloud field imposes. The HMAC hashes the counter as eight bytes, so
        // the whole range has to be encodable without trapping.
        for counter in [UInt64(Int64.max), UInt64(Int64.max) + 1, UInt64.max] {
            let code = OTPGenerator.generateHOTP(secret: sha1Secret, digits: 6, counter: counter)
            XCTAssertEqual(code.count, 6, "counter \(counter)")
        }
    }

    // MARK: - Defaults and boundaries

    func testDefaultsAreSHA1SixDigitsThirtySeconds() {
        let at = Date(timeIntervalSince1970: 60)

        let implicit = OTPGenerator.generateOTP(secret: sha1Secret, now: at)
        let explicit = OTPGenerator.generateOTP(secret: sha1Secret, algorithm: .sha1,
                                                digits: 6, period: 30, now: at)

        XCTAssertEqual(implicit, explicit)
        XCTAssertEqual(implicit, "359152")
    }

    func testACodeIsStableWithinItsPeriodAndChangesAtTheBoundary() {
        let start = Date(timeIntervalSince1970: 60)
        let lastMoment = Date(timeIntervalSince1970: 89.999)
        let nextPeriod = Date(timeIntervalSince1970: 90)

        func at(_ moment: Date) -> String {
            OTPGenerator.generateOTP(secret: sha1Secret, digits: 6, period: 30, now: moment)
        }

        XCTAssertEqual(at(start), at(lastMoment))
        XCTAssertNotEqual(at(start), at(nextPeriod))
    }

    func testAPre1970InstantDoesNotTrap() {
        // The counter is derived from a `UInt64`; a negative interval would be a
        // conversion trap rather than a bad code.
        let before1970 = Date(timeIntervalSince1970: -1)

        XCTAssertEqual(
            OTPGenerator.generateOTP(secret: sha1Secret, digits: 6, period: 30, now: before1970),
            OTPGenerator.generateOTP(secret: sha1Secret, digits: 6, period: 30,
                                     now: Date(timeIntervalSince1970: 0))
        )
    }

    // MARK: - Malformed input must not trap

    func testDigitCountsThatUsedToCrashNowProduceACode() {
        // Every one of these trapped before. `UInt32(pow(10, Float(digits)))`
        // overflowed for 10 and up, and `pow` returning 0.1 made the modulus zero
        // for anything negative — a division by zero. Reaching the assertions at all
        // is most of the proof, since a trap would take the whole bundle down.
        for digits in [10, 11, 12, 19, 0, -1, -100, Int.max, Int.min] {
            let code = OTPGenerator.generateOTP(secret: sha1Secret, digits: digits,
                                                now: Date(timeIntervalSince1970: 60))

            XCTAssertFalse(code.isEmpty, "digits=\(digits) produced nothing")
        }
    }

    func testPeriodsThatUsedToCrashNowProduceACode() {
        // Zero divided to infinity and negatives went below `UInt64.min`; both were
        // conversion traps in the counter.
        for period in [0, -1, -30, Int.min] {
            let code = OTPGenerator.generateOTP(secret: sha1Secret, period: period,
                                                now: Date(timeIntervalSince1970: 60))

            XCTAssertEqual(code.count, 6, "period=\(period)")
        }
    }

    func testEffectiveDigitsClampsIntoTheRepresentableRange() {
        XCTAssertEqual(OTPGenerator.effectiveDigits(6), 6)
        XCTAssertEqual(OTPGenerator.effectiveDigits(8), 8)
        XCTAssertEqual(OTPGenerator.effectiveDigits(19), 19)
        XCTAssertEqual(OTPGenerator.effectiveDigits(20), 19)
        XCTAssertEqual(OTPGenerator.effectiveDigits(0), 1)
        XCTAssertEqual(OTPGenerator.effectiveDigits(-5), 1)
        XCTAssertEqual(OTPGenerator.effectiveDigits(Int.max), 19)
        XCTAssertEqual(OTPGenerator.effectiveDigits(Int.min), 1)
    }

    func testEffectivePeriodFallsBackToThirty() {
        XCTAssertEqual(OTPGenerator.effectivePeriod(60), 60)
        XCTAssertEqual(OTPGenerator.effectivePeriod(1), 1)
        XCTAssertEqual(OTPGenerator.effectivePeriod(0), 30)
        XCTAssertEqual(OTPGenerator.effectivePeriod(-30), 30)
        XCTAssertEqual(OTPGenerator.effectivePeriod(Int.min), 30)
    }

    func testWiderDigitCountsAreZeroPaddedViewsOfTheSameValue() {
        // The modulus only ever drops leading digits, so 8/9/10 digits are views of
        // one truncated value. This is also the case that used to crash, and it
        // confirms ten digits is *correct* rather than clamped to eight.
        let at = Date(timeIntervalSince1970: 60)
        let eight = OTPGenerator.generateOTP(secret: sha1Secret, digits: 8, now: at)
        let nine = OTPGenerator.generateOTP(secret: sha1Secret, digits: 9, now: at)
        let ten = OTPGenerator.generateOTP(secret: sha1Secret, digits: 10, now: at)

        XCTAssertEqual(eight, "37359152")
        XCTAssertEqual(nine, "137359152")
        XCTAssertEqual(ten, "0137359152")
        XCTAssertTrue(nine.hasSuffix(eight))
    }

    // MARK: - Algorithm identity

    func testAlgorithmRawValuesAreStable() {
        // These strings are what goes into the CloudKit `algorithm` field and into
        // an otpauth URL, so changing one silently orphans existing records.
        XCTAssertEqual(OTPAlgorithm.sha1.rawValue, "SHA1")
        XCTAssertEqual(OTPAlgorithm.sha256.rawValue, "SHA256")
        XCTAssertEqual(OTPAlgorithm.sha512.rawValue, "SHA512")

        XCTAssertEqual(OTPAlgorithm(rawValue: "SHA256"), .sha256)
        XCTAssertEqual(OTPAlgorithm(rawValue: "SHA512"), .sha512)
        XCTAssertEqual(OTPAlgorithm.allCases.count, 3)
    }

    // MARK: - Base32

    func testBase32EncodingMatchesKnownValues() {
        // RFC 4648 section 10.
        XCTAssertEqual(OTPGenerator.encodeBase32(Data("foobar".utf8)), "MZXW6YTBOI")
        XCTAssertEqual(OTPGenerator.encodeBase32(Data("f".utf8)), "MY")
    }
}
