// ToneBandTests.swift: `mappingStraight`, the per-pixel loop every colour op
// shares, runs its rows in parallel bands. The bands must not change a bit of
// the result (each equals the op on one pixel at a time) and a non-finite
// result must still throw naming the lowest bad index, as the one-band loop did.
@testable import CoreRaster
import Testing

@Suite struct ToneBandTests {
    /// A per-pixel transform with some arithmetic in it, keeping alpha.
    static let twist: @Sendable (RGBA) -> RGBA = { p in
        RGBA(r: p.g * 0.75 + p.b * 0.25, g: p.r * p.r, b: 1 - p.b * 0.5, a: p.a)
    }

    /// The op one pixel at a time, as the loop before bands ran it.
    static func reference(_ b: PixelBuffer, _ transform: (RGBA) -> RGBA) throws -> [RGBA] {
        try (0..<b.height).flatMap { y in
            try (0..<b.width).map { x in
                let p = try b.pixel(x: x, y: y)
                return p.a == 0 ? p : transform(p.unpremultiplied()).premultiplied()
            }
        }
    }

    static func pixels(_ b: PixelBuffer) throws -> [RGBA] {
        try (0..<b.height).flatMap { y in try (0..<b.width).map { x in try b.pixel(x: x, y: y) } }
    }

    @Test func everyBandCountMatchesThePixelReference() throws {
        let b = try ToneCheck.seeded(width: 23, height: 37, seed: 0xBA4D)
        let expected = try Self.reference(b, Self.twist)
        for bands in [1, 2, 3, 7, 36, 37, 64] {
            #expect(try Self.pixels(b.mappingStraight(bands: bands, Self.twist)) == expected, "\(bands) bands")
        }
    }

    /// An odd-height buffer large enough for the default to use several bands:
    /// a real op equals that op on each pixel alone.
    @Test func defaultBandsMatchOnePixelAtATime() throws {
        let b = try ToneCheck.seeded(width: 331, height: 203, seed: 0x0DD)
        #expect(b.width * b.height / PixelBuffer.pixelsPerBand >= 2)
        let out = try Self.pixels(b.vibrance(40))
        let expected = try Self.pixels(b).map { p in
            try PixelBuffer(width: 1, height: 1, fill: p).vibrance(40).pixel(x: 0, y: 0)
        }
        #expect(out == expected)
    }

    /// Markers in several bands turn NaN; the error names the lowest index.
    @Test func nonFiniteThrowsTheLowestIndex() throws {
        var b = try ToneCheck.seeded(width: 23, height: 37, seed: 0xBA4D, opaque: true)
        let marker = RGBA(r: 2, g: 0, b: 0, a: 1)
        for (x, y) in [(4, 30), (9, 11), (0, 22), (17, 6), (3, 35)] { try b.setPixel(x: x, y: y, marker) }
        for bands in [1, 2, 5, 7, 37] {
            let error = #expect(throws: RasterError.self) {
                try b.mappingStraight(bands: bands) { p in p.r == 2 ? RGBA(r: .nan, g: 0, b: 0, a: 1) : p }
            }
            guard case .invalid(let why) = error else {
                Issue.record("\(bands) bands: expected .invalid, got \(String(describing: error))")
                continue
            }
            #expect(why.contains("at index \(6 * 23 + 17):"), "\(bands) bands: \(why)")
        }
    }
}
