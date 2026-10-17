// HalfFloatTests.swift: the binary16 converter the Metal backend uses for
// rgba16Float textures. Exact bit patterns for the named values (zeros, powers
// of two, the largest finite, the smallest subnormal, infinities, NaN), exact
// decodes, ties-to-even at both a round-down and a round-up tie, a seeded
// round trip within half an ulp, and the exhaustive identity over every finite
// binary16 pattern.
import CoreRender
import Testing

@Suite struct HalfFloatTests {
    @Test func encodesTheNamedValuesToTheirExactBitPatterns() {
        #expect(HalfFloat.encode(0) == 0x0000)
        #expect(HalfFloat.encode(-0.0) == 0x8000)
        #expect(HalfFloat.encode(1) == 0x3C00)
        #expect(HalfFloat.encode(0.5) == 0x3800)
        #expect(HalfFloat.encode(-2) == 0xC000)
        #expect(HalfFloat.encode(65504) == 0x7BFF)
        #expect(HalfFloat.encode(1 / 3) == 0x3555)
        #expect(HalfFloat.encode(0x1p-24) == 0x0001)
        #expect(HalfFloat.encode(0x1p-14) == 0x0400)
        #expect(HalfFloat.encode(2047.5) == 0x6800, "rounding carries into the exponent: 2047.5 is 2048")
        #expect(HalfFloat.encode(Float.infinity) == 0x7C00)
        #expect(HalfFloat.encode(-Float.infinity) == 0xFC00)
        #expect(HalfFloat.encode(65520) == 0x7C00, "the tie above the largest finite rounds to even, which is infinity")
        #expect(HalfFloat.encode(65519) == 0x7BFF)
        #expect(HalfFloat.encode(100_000) == 0x7C00)
        #expect(HalfFloat.encode(1e30) == 0x7C00)
        #expect(HalfFloat.encode(Float.greatestFiniteMagnitude) == 0x7C00)
        #expect(HalfFloat.encode(-Float.greatestFiniteMagnitude) == 0xFC00)
        #expect(HalfFloat.encode(0x1p-25) == 0x0000, "half the smallest subnormal ties to even, which is zero")
        #expect(HalfFloat.encode(-0x1p-25) == 0x8000)
        #expect(HalfFloat.encode(0x1p-25 * 1.5) == 0x0001, "rounds up from below the smallest subnormal")
        #expect(HalfFloat.encode(Float.leastNonzeroMagnitude) == 0x0000)
    }

    @Test func encodesNaNAsAQuietNaNWithTheSignKept() {
        for (value, sign): (Float, UInt16) in [(.nan, 0), (-.nan, 0x8000), (.signalingNaN, 0)] {
            let bits = HalfFloat.encode(value)
            #expect(bits & 0x8000 == sign)
            #expect(bits & 0x7C00 == 0x7C00)
            #expect(bits & 0x03FF != 0, "a NaN keeps a nonzero fraction, else it would read as infinity")
            #expect(bits & 0x0200 == 0x0200, "the quiet bit is set")
            #expect(HalfFloat.decode(bits).isNaN)
        }
    }

    @Test func decodesExactly() {
        #expect(HalfFloat.decode(0x0000) == 0)
        #expect(HalfFloat.decode(0x8000) == 0 && HalfFloat.decode(0x8000).sign == .minus)
        #expect(HalfFloat.decode(0x3C00) == 1)
        #expect(HalfFloat.decode(0x3555) == 0.333251953125)
        #expect(HalfFloat.decode(0x0001) == 0x1p-24)
        #expect(HalfFloat.decode(0x0001) == 5.9604644775390625e-08)
        #expect(HalfFloat.decode(0x03FF) == 0.000060975551605224609375, "the largest subnormal")
        #expect(HalfFloat.decode(0x0400) == 0x1p-14)
        #expect(HalfFloat.decode(0x7BFF) == 65504)
        #expect(HalfFloat.decode(0xFBFF) == -65504)
        #expect(HalfFloat.decode(0x7C00) == Float.infinity)
        #expect(HalfFloat.decode(0xFC00) == -Float.infinity)
        #expect(HalfFloat.decode(0x7C01).isNaN)
        #expect(HalfFloat.decode(0xFE00).isNaN)
    }

    @Test func roundsTiesToEven() {
        // Exactly halfway between 1 and the next half: the even neighbour is 0x3C00.
        #expect(HalfFloat.encode(HalfFloat.decode(0x3C00) + 0x1p-11) == 0x3C00)
        // Exactly halfway between 0x3C01 and 0x3C02: the even neighbour is 0x3C02.
        #expect(HalfFloat.encode(HalfFloat.decode(0x3C01) + 0x1p-11) == 0x3C02)
        // Just above and just below the first tie go to the nearer half.
        #expect(HalfFloat.encode(HalfFloat.decode(0x3C00) + 0x1p-11 + 0x1p-20) == 0x3C01)
        #expect(HalfFloat.encode(HalfFloat.decode(0x3C00) + 0x1p-11 - 0x1p-20) == 0x3C00)
        // The same two ties inside the subnormal range (units of 2^-24).
        #expect(HalfFloat.encode(2.5 * 0x1p-24) == 0x0002)
        #expect(HalfFloat.encode(3.5 * 0x1p-24) == 0x0004)
    }

    @Test func seededRoundTripStaysWithinHalfAnUlp() {
        var rng = SplitMix64(seed: 16)
        for _ in 0..<2000 {
            let x = Float.random(in: 0...1, using: &rng)
            let back = HalfFloat.decode(HalfFloat.encode(x))
            #expect(abs(back - x) <= x * 0x1p-11 + 0x1p-25, "\(x) came back as \(back)")
        }
        for _ in 0..<2000 {
            let x = Float.random(in: -65504...65504, using: &rng)
            guard abs(x) >= 0x1p-14 else { continue }
            let back = HalfFloat.decode(HalfFloat.encode(x))
            #expect(back.isFinite)
            #expect(abs(back - x) <= abs(x) * 0x1p-11, "\(x) came back as \(back)")
            #expect(back.sign == x.sign)
        }
    }

    @Test func everyFiniteBitPatternSurvivesDecodeThenEncode() {
        var finite = 0
        var nan = 0
        for bits in UInt16.min...UInt16.max {
            let value = HalfFloat.decode(bits)
            if value.isFinite {
                finite += 1
                #expect(HalfFloat.encode(value) == bits, "0x\(String(bits, radix: 16))")
            } else if value.isNaN {
                nan += 1
                #expect(bits & 0x7C00 == 0x7C00 && bits & 0x03FF != 0)
            } else {
                #expect(bits == 0x7C00 || bits == 0xFC00)
            }
        }
        #expect(finite == 65536 - 2048, "every pattern but the two infinities and 2046 NaNs")
        #expect(nan == 2046)
    }
}
