// DisplayTransferTests.swift: the table-based 8-bit display transfer against
// the reference it replaces, `Color3.converted` plus the clamp-and-round byte
// rule, with `==`: every decode byte, seeded triples, a million seeded
// encodes, both sides of every encode threshold, NaN and infinities. In an
// optimized build, every Float in 0...1 is also checked in sRGB.
@testable import CoreColor
import Foundation
import Testing

#if DEBUG
private let optimized = false
#else
private let optimized = true
#endif

/// Seeded generator; the same algorithm as FlareCoreTests' `SplitMix64`, which
/// this test target cannot import.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private let spaces: [ColorSpace] = [.sRGB, .displayP3]

/// DisplayBytes' byte rule for a value already in 0...1.
private func referenceByte(_ v: Double) -> UInt8 {
    UInt8((v * 255).rounded())
}

private func referenceDecode(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ space: ColorSpace) throws -> Color3 {
    try Color3(Double(r) / 255, Double(g) / 255, Double(b) / 255).converted(from: space, to: .linearSRGB)
}

private func referenceEncode(_ c: Color3, _ space: ColorSpace) throws -> [UInt8] {
    let e = try c.converted(from: .linearSRGB, to: space).clampedToUnit()
    return [referenceByte(e.c0), referenceByte(e.c1), referenceByte(e.c2)]
}

private func encoded(_ t: DisplayTransfer, _ c: Color3) -> [UInt8] {
    let (r, g, b) = t.encode(c)
    return [r, g, b]
}

@Test func decodeEqualsConvertedOnEverySRGBByte() throws {
    let t = try DisplayTransfer(.sRGB)
    for v in 0...255 {
        let r = UInt8(v), g = UInt8((v + 85) % 256), b = UInt8((v + 170) % 256)
        #expect(t.decode(r, g, b) == (try referenceDecode(r, g, b, .sRGB)), "bytes \(r), \(g), \(b)")
    }
}

@Test func decodeEqualsConvertedInDisplayP3() throws {
    let t = try DisplayTransfer(.displayP3)
    var triples: [(UInt8, UInt8, UInt8)] = []
    for v in UInt8.min...UInt8.max {
        triples.append((v, v, v))
        for other: UInt8 in [0, 128, 255] {
            triples += [(v, other, other), (other, v, other), (other, other, v)]
        }
    }
    var rng = SplitMix64(seed: 309)
    for _ in 0..<100_000 {
        let n = rng.next()
        triples.append((UInt8(truncatingIfNeeded: n), UInt8(truncatingIfNeeded: n >> 8), UInt8(truncatingIfNeeded: n >> 16)))
    }
    var mismatches = 0
    for (r, g, b) in triples where t.decode(r, g, b) != (try referenceDecode(r, g, b, .displayP3)) {
        mismatches += 1
        if mismatches <= 5 { Issue.record("P3 bytes \(r), \(g), \(b) decode differently") }
    }
    #expect(mismatches == 0)
}

@Test(arguments: spaces)
func encodeEqualsReferenceOnSeededValues(_ space: ColorSpace) throws {
    let t = try DisplayTransfer(space)
    var rng = SplitMix64(seed: space == .sRGB ? 3091 : 3092)
    var mismatches = 0
    // 1,000,000 seeded Doubles, three per color.
    for _ in 0..<333_334 {
        let c = Color3(.random(in: -0.5...1.5, using: &rng), .random(in: -0.5...1.5, using: &rng),
                       .random(in: -0.5...1.5, using: &rng))
        if encoded(t, c) != (try referenceEncode(c, space)) {
            mismatches += 1
            if mismatches <= 5 { Issue.record("\(space) encode of \(c) differs") }
        }
    }
    #expect(mismatches == 0)
}

@Test func everyThresholdIsTheLeastValueReachingItsByte() {
    let least = DisplayTransfer.least
    #expect(least.count == 256)
    for k in 1...255 {
        #expect(Int(DisplayTransfer.step(least[k])) == k, "least[\(k)] = \(least[k])")
        #expect(Int(DisplayTransfer.step(least[k].nextDown)) == k - 1, "below least[\(k)]")
    }
}

@Test(arguments: spaces)
func encodeEqualsReferenceOnBothSidesOfEveryThreshold(_ space: ColorSpace) throws {
    let t = try DisplayTransfer(space)
    for k in 1...255 {
        for v in [DisplayTransfer.least[k], DisplayTransfer.least[k].nextDown] {
            // In P3 the threshold applies after the matrix: start from the P3 value.
            let colors = space == .sRGB
                ? [Color3(v, v, v), Color3(v, 0, 1)]
                : [Matrix3.linearSRGBFromP3 * Color3(v, v, v), Matrix3.linearSRGBFromP3 * Color3(v, 0, 1)]
            for c in colors {
                #expect(encoded(t, c) == (try referenceEncode(c, space)), "\(space) k \(k) at \(v)")
            }
        }
        if space == .sRGB {
            let v = DisplayTransfer.least[k]
            #expect(encoded(t, Color3(v, v.nextDown, v)) == [UInt8(k), UInt8(k - 1), UInt8(k)])
        }
    }
}

@Test func nanGivesZeroAndInfinitiesClamp() throws {
    let s = try DisplayTransfer(.sRGB)
    #expect(encoded(s, Color3(.nan, .infinity, -.infinity)) == [0, 255, 0])
    #expect(encoded(s, Color3(-0.0, 2, -1)) == [0, 255, 0])
    let p3 = try DisplayTransfer(.displayP3)
    #expect(encoded(p3, Color3(.nan, .nan, .nan)) == [0, 0, 0])
    _ = p3.encode(Color3(.infinity, -.infinity, .infinity))  // must not trap
    #expect(DisplayTransfer.byte(.nan) == 0)
    #expect(DisplayTransfer.byte(.infinity) == 255)
    #expect(DisplayTransfer.byte(-.infinity) == 0)
}

@Test func byteIsTheClampAndRoundRule() {
    var rng = SplitMix64(seed: 3093)
    for _ in 0..<10_000 {
        let v = Double.random(in: -0.5...1.5, using: &rng)
        #expect(DisplayTransfer.byte(v) == referenceByte(min(max(v, 0), 1)), "\(v)")
    }
    for k in 0...255 {
        let v = Double(k) / 255
        #expect(DisplayTransfer.byte(v) == UInt8(k))
        let half = min((Double(k) + 0.5) / 255, 1)
        #expect(DisplayTransfer.byte(half) == referenceByte(half))
    }
}

@Test func onlyDisplaySpacesAreAccepted() throws {
    for space in ColorSpace.allCases {
        if spaces.contains(space) {
            #expect(try DisplayTransfer(space).space == space)
        } else {
            #expect(throws: ColorError.self) { try DisplayTransfer(space) }
        }
    }
}

/// Every Float in 0...1, about 1.07 billion values, in sRGB.
@Suite(.serialized, .enabled(if: optimized, "the exhaustive Float sweep needs an optimized build"))
struct DisplayTransferExhaustiveTests {
    @Test func everyFloatInZeroToOneEncodesToTheReferenceByte() async throws {
        let t = try DisplayTransfer(.sRGB)
        let end = UInt64((1 as Float).bitPattern) + 1
        let chunks: UInt64 = 64
        let size = (end + chunks - 1) / chunks
        let mismatches = try await withThrowingTaskGroup(of: Int.self) { group in
            for chunk in 0..<chunks {
                group.addTask {
                    var bad = 0
                    var bits = chunk * size
                    while bits < min(end, (chunk + 1) * size) {
                        let c = Color3(Double(Float(bitPattern: UInt32(bits))), 0, 0)
                        if t.encode(c).0 != (try referenceEncode(c, .sRGB))[0] { bad += 1 }
                        bits += 1
                    }
                    return bad
                }
            }
            return try await group.reduce(0, +)
        }
        #expect(mismatches == 0)
    }
}
