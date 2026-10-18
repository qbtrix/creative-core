// ImportNumberTests.swift: ImportNumber.decimal, the importers' fast path for decimals, gives
// exactly `Double(String)`'s bits wherever it answers, and answers for the short decimals files
// are mostly made of.
import Testing
@testable import FlareCore

struct ImportNumberTests {
    func fast(_ text: String) -> Double? {
        let bytes = Array(text.utf8)
        return ImportNumber.decimal(bytes, 0..<bytes.count)
    }

    /// Seeded decimals of 1 to 19 digits, with a point anywhere, a sign and an exponent or not.
    @Test func matchesDoubleParsingBitForBit() {
        var rng = SplitMix64(seed: 0x4E55_4D42)
        var answered = 0
        for i in 0..<20_000 {
            let count = Int.random(in: 1...19, using: &rng)
            var digits = (0..<count).map { _ in String(Int.random(in: 0...9, using: &rng)) }.joined()
            if Bool.random(using: &rng) { digits.insert(".", at: digits.index(digits.startIndex, offsetBy: Int.random(in: 1...count, using: &rng))) }
            if digits.hasSuffix(".") { digits += "0" }
            var text = (Int.random(in: 0..<4, using: &rng) == 0 ? "-" : "") + digits
            if Bool.random(using: &rng) { text += (Bool.random(using: &rng) ? "e" : "E") + String(Int.random(in: -30...30, using: &rng)) }
            guard let value = fast(text) else { continue }
            answered += 1
            #expect(value.bitPattern == Double(text)?.bitPattern, "case \(i): \(text)")
        }
        #expect(answered > 10_000)
    }

    @Test func edgesMatchOrDecline() {
        // 2^53 is the largest significand taken; 1e22 the largest power.
        for text in ["0", "-0", "0.58", "100", "9007199254740992", "1e22", "-1e-22", "0.000000000000000000001", "1E+3"] {
            #expect(fast(text)?.bitPattern == Double(text)?.bitPattern, "\(text)")
        }
        for text in ["9007199254740993", "1e23", "1e-23", "12345678901234567890", "", "-", ".", "1e", "1e+", "1x", "1.2.3", "1e99999"] {
            #expect(fast(text) == nil, "\(text)")
        }
    }
}
