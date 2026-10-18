// ImportNumber.swift: the exact fast path the importers try before `Double(String)`.
//
// The caller has already matched a decimal by its grammar (sign? digits ('.' digits?)?
// exponent?). When the significand, its digits read as one integer, is at most 2^53 and its
// power of ten is within ±22, the significand and the power are exact doubles, so one
// multiply or divide rounds once: the correctly rounded value, the one `Double(String)`
// returns (Clinger's fast path). Anything else returns nil and the caller asks `Double(String)`.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

enum ImportNumber {
    /// The largest significand read here: every integer up to 2^53 is an exact double.
    static let maxSignificand: UInt64 = 1 << 53
    /// The most significant digits gathered before giving up: 19 digits always fit in a UInt64.
    static let maxDigits = 19
    /// 10^0 through 10^22, each exact as a double.
    static let powers: [Double] = [1e0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10, 1e11,
                                   1e12, 1e13, 1e14, 1e15, 1e16, 1e17, 1e18, 1e19, 1e20, 1e21, 1e22]

    /// The decimal in `bytes[range]`, or nil when it is outside the fast path.
    static func decimal(_ bytes: [UInt8], _ range: Range<Int>) -> Double? {
        guard range.lowerBound >= 0, range.upperBound <= bytes.count else { return nil }
        var i = range.lowerBound, negative = false, dot = false, any = false
        var significand: UInt64 = 0, digits = 0, scale = 0
        if i < range.upperBound, bytes[i] == UInt8(ascii: "-") || bytes[i] == UInt8(ascii: "+") {
            negative = bytes[i] == UInt8(ascii: "-")
            i += 1
        }
        while i < range.upperBound {
            let c = bytes[i]
            if c >= UInt8(ascii: "0") && c <= UInt8(ascii: "9") {
                any = true
                if significand != 0 || c != UInt8(ascii: "0") { digits += 1 }
                guard digits <= maxDigits else { return nil }
                significand = significand * 10 + UInt64(c - UInt8(ascii: "0"))
                if dot { scale -= 1 }
            } else if c == UInt8(ascii: "."), !dot {
                dot = true
            } else { break }
            i += 1
        }
        if i < range.upperBound {
            guard bytes[i] == UInt8(ascii: "e") || bytes[i] == UInt8(ascii: "E") else { return nil }
            i += 1
            var exponentSign = 1, exponent = 0, count = 0
            if i < range.upperBound, bytes[i] == UInt8(ascii: "-") || bytes[i] == UInt8(ascii: "+") {
                exponentSign = bytes[i] == UInt8(ascii: "-") ? -1 : 1
                i += 1
            }
            while i < range.upperBound, count < 4, bytes[i] >= UInt8(ascii: "0") && bytes[i] <= UInt8(ascii: "9") {
                exponent = exponent * 10 + Int(bytes[i] - UInt8(ascii: "0"))
                count += 1
                i += 1
            }
            guard count > 0 else { return nil }
            scale += exponentSign * exponent
        }
        guard any, i == range.upperBound, significand <= maxSignificand, scale >= -22, scale <= 22 else { return nil }
        let power = powers[abs(scale)]
        let value = scale < 0 ? Double(significand) / power : Double(significand) * power
        return negative ? -value : value
    }
}
