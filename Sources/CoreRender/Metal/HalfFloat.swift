// HalfFloat.swift: IEEE 754 binary16 ("half") encode and decode, in pure bit
// math on UInt16 and Float bit patterns. The Metal backend fills rgba16Float
// tile textures from Float32 pixel buffers and reads them back through it;
// Float16 is unavailable on x86_64 macOS, so this stays portable and is tested
// on Linux. Layout: 1 sign bit, 5 exponent bits (bias 15), 10 fraction bits.
// Invariants: encode is round-to-nearest, ties to even, over the dropped Float
// fraction bits, and the round-up carries into the exponent (2047.5 is 2048,
// 65520 is infinity); every binary16 is a Float, so decode is exact and
// encode(decode(bits)) == bits for every finite pattern, both zeros and every
// subnormal included; NaN stays NaN (quiet, sign kept) and never reads back as
// infinity.

/// IEEE 754 binary16 encode and decode. Values below `0x1p-25` in magnitude
/// round to a signed zero; `0x1p-24` is the smallest subnormal and 65504
/// (`0x7BFF`) the largest finite half.
public enum HalfFloat {
    /// Binary16 bias: the exponent field holds the unbiased exponent plus 15.
    private static let bias = 15
    /// Float32 bias, for the unbiased exponent of a Float's bit pattern.
    private static let floatBias = 127
    /// The exponent field of an infinity or NaN, shifted into place.
    private static let infinity: UInt16 = 0x7C00
    /// The Float's implicit leading bit, above its 23 fraction bits.
    private static let implicitBit: UInt32 = 0x80_0000

    /// Nearest binary16 to `value`, ties to even. |value| >= 65520 gives
    /// ±infinity; NaN stays NaN (a quiet NaN with the sign kept); subnormals
    /// down to 2^-24 are kept, smaller round to ±0.
    public static func encode(_ value: Float) -> UInt16 {
        let bits = value.bitPattern
        let sign = UInt16(truncatingIfNeeded: bits >> 16) & 0x8000
        let floatExponent = Int((bits >> 23) & 0xFF)
        let fraction = bits & 0x7F_FFFF
        if floatExponent == 0xFF {
            // Infinity, or a NaN: keep the top payload bits and set the quiet bit
            // so the fraction is never zero.
            let payload: UInt16 = fraction == 0 ? 0 : 0x0200 | UInt16(fraction >> 13)
            return sign | infinity | payload
        }
        if floatExponent == 0 {
            // A Float subnormal is below 2^-126, far under the half range.
            return sign
        }
        let exponent = floatExponent - floatBias + bias
        guard exponent < 31 else { return sign | infinity }
        if exponent >= 1 {
            // Normal: keep 10 of the 23 fraction bits and round on the 13 dropped.
            let mantissa = fraction >> 13
            let rest = fraction & 0x1FFF
            var result = UInt16(exponent << 10) | UInt16(mantissa)
            if roundsUp(rest: rest, halfway: 0x1000, mantissa: mantissa) { result &+= 1 }
            return sign | result
        }
        // Subnormal: the implicit bit joins the fraction and the whole thing
        // shifts right until the unit is 2^-24. A round-up may carry into the
        // smallest normal, 0x0400, which is the right neighbour.
        let shift = 1 - exponent + 13
        guard shift <= 24 else { return sign }
        let full = implicitBit | fraction
        let mantissa = full >> shift
        let rest = full & ((1 << shift) - 1)
        var result = UInt16(mantissa)
        if roundsUp(rest: rest, halfway: 1 << (shift - 1), mantissa: mantissa) { result &+= 1 }
        return sign | result
    }

    /// The Float the binary16 `bits` denote, exactly (every binary16 is a Float).
    public static func decode(_ bits: UInt16) -> Float {
        let sign = UInt32(bits & 0x8000) << 16
        let exponent = Int((bits >> 10) & 0x1F)
        let fraction = UInt32(bits & 0x3FF)
        if exponent == 0x1F {
            // Infinity, or a NaN whose payload moves to the top of the Float fraction.
            return Float(bitPattern: sign | 0x7F80_0000 | (fraction << 13))
        }
        if exponent == 0 {
            // Zero or subnormal: `fraction` units of 2^-24, exact in a Float.
            let magnitude = Float(fraction) * 0x1p-24
            return Float(bitPattern: sign | magnitude.bitPattern)
        }
        let floatExponent = UInt32(exponent - bias + floatBias)
        return Float(bitPattern: sign | (floatExponent << 23) | (fraction << 13))
    }

    /// Round-to-nearest, ties to even: whether dropping `rest` (the bits below
    /// the kept `mantissa`, where `halfway` is the lowest dropped position)
    /// rounds the kept bits up by one.
    private static func roundsUp(rest: UInt32, halfway: UInt32, mantissa: UInt32) -> Bool {
        rest > halfway || (rest == halfway && mantissa & 1 == 1)
    }
}
