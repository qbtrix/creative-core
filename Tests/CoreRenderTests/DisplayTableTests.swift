// DisplayTableTests.swift: the Float threshold tables the Metal display kernel reads, and `encode`,
// the kernel's Swift mirror. Every threshold is the first Float at its level (its predecessor sits one
// level lower), checked against `DisplayTransfer` itself; sRGB encodes equal `PixelBuffer.rgba8`
// exactly for seeded pixels and edge values, and follow its per-pixel rule on non-finite values;
// Display P3 is within one byte of it; every byte value per channel survives decode, rgba16Float
// storage and encode in both spaces; other spaces throw.
import CoreColor
import CoreRaster
import CoreRender
import Testing

@Suite struct DisplayTableTests {
    @Test func everyThresholdIsTheFirstFloatAtItsLevel() throws {
        let table = try DisplayTable(.sRGB)
        let transfer = try DisplayTransfer(.sRGB)
        #expect(table.thresholds.count == 2 * DisplayTable.levels)
        for k in 1...DisplayTable.levels {
            let curve = table.thresholds[k - 1]
            let alpha = table.thresholds[DisplayTable.alphaBase + k - 1]
            #expect(Int(transfer.encode(Color3(Double(curve), 0, 0)).0) == k)
            #expect(Int(transfer.encode(Color3(Double(curve.nextDown), 0, 0)).0) == k - 1)
            #expect(Int(DisplayTransfer.byte(Double(alpha))) == k)
            #expect(Int(DisplayTransfer.byte(Double(alpha.nextDown))) == k - 1)
            #expect(Int(DisplayTable.level(curve, table.thresholds, base: 0)) == k)
            #expect(Int(DisplayTable.level(curve.nextDown, table.thresholds, base: 0)) == k - 1)
            #expect(Int(DisplayTable.level(alpha, table.thresholds, base: DisplayTable.alphaBase)) == k)
            #expect(Int(DisplayTable.level(alpha.nextDown, table.thresholds, base: DisplayTable.alphaBase)) == k - 1)
        }
    }

    @Test func levelHandlesTheEdgesAndAShortTable() throws {
        let table = try DisplayTable(.sRGB).thresholds
        #expect(DisplayTable.level(.nan, table, base: 0) == 0)
        #expect(DisplayTable.level(-1, table, base: 0) == 0)
        #expect(DisplayTable.level(.infinity, table, base: 0) == 255)
        #expect(DisplayTable.level(2, table, base: DisplayTable.alphaBase) == 255)
        #expect(DisplayTable.level(1, [], base: 0) == 0)
        #expect(DisplayTable.level(1, table, base: DisplayTable.alphaBase + 1) == 0)
    }

    @Test func sRGBEncodeEqualsTheCPUBytesExactly() throws {
        let pixels = Self.pixels()
        let expected = try Self.buffer(pixels).rgba8(colorSpace: .sRGB)
        let table = try DisplayTable(.sRGB)
        #expect(table.matrix == nil)
        #expect(pixels.flatMap { table.encode($0) } == expected)
    }

    /// A buffer holds finite values only, but a texture may hold NaN or infinity: those follow
    /// `rgba8`'s per-pixel rule (unpremultiply, `DisplayTransfer.encode`, `byte` for alpha).
    @Test func sRGBEncodeFollowsTheCPURuleOnNonFiniteValues() throws {
        let table = try DisplayTable(.sRGB)
        let transfer = try DisplayTransfer(.sRGB)
        let edges = [RGBA(r: .nan, g: 0.5, b: -1, a: 1), RGBA(r: 0.3, g: 0.3, b: 0.3, a: .nan),
                     RGBA(r: .infinity, g: -.infinity, b: 0.25, a: 1), RGBA(r: 0.2, g: 0.1, b: 0, a: .infinity),
                     RGBA(r: 0.5, g: .nan, b: 0.5, a: 0)]
        for p in edges {
            let s = p.unpremultiplied()
            let (r, g, b) = transfer.encode(Color3(Double(s.r), Double(s.g), Double(s.b)))
            #expect(table.encode(p) == [r, g, b, DisplayTransfer.byte(Double(s.a))], "\(p)")
        }
    }

    @Test func displayP3EncodeIsWithinOneByteOfTheCPU() throws {
        let pixels = Self.pixels()
        let expected = try Self.buffer(pixels).rgba8(colorSpace: .displayP3)
        let table = try DisplayTable(.displayP3)
        #expect(table.matrix?.count == 9)
        let actual = pixels.flatMap { table.encode($0) }
        let worst = zip(actual, expected).map { abs(Int($0) - Int($1)) }.max() ?? 0
        #expect(actual.count == expected.count)
        #expect(worst <= 1)
    }

    @Test(arguments: [ColorSpace.sRGB, .displayP3])
    func everyByteValuePerChannelRoundTripsThroughHalfStorage(_ space: ColorSpace) throws {
        var bytes: [UInt8] = []
        for channel in 0..<4 {
            for v in 0...255 {
                var px: [UInt8] = channel == 3 ? [255, 255, 255, 0] : [0, 0, 0, 255]
                px[channel] = UInt8(v)
                bytes += px
            }
        }
        let buffer = try PixelBuffer(rgba8: bytes, width: 256, height: 4, colorSpace: space)
        let table = try DisplayTable(space)
        let half = { (v: Float) in HalfFloat.decode(HalfFloat.encode(v)) }
        var encoded: [UInt8] = []
        for i in 0..<(256 * 4) {
            let p = try buffer.pixel(x: i % 256, y: i / 256)
            encoded += table.encode(RGBA(r: half(p.r), g: half(p.g), b: half(p.b), a: half(p.a)))
        }
        // Alpha 0 carries no color, so (255, 255, 255, 0) comes back as all zeros, as the CPU encodes it.
        var expected = bytes
        expected.replaceSubrange((3 * 256 * 4)..<(3 * 256 * 4 + 4), with: [0, 0, 0, 0])
        let wrong = (0..<(256 * 4)).filter { i in encoded[(i * 4)..<(i * 4 + 4)] != expected[(i * 4)..<(i * 4 + 4)] }
        #expect(wrong.isEmpty, "pixels \(wrong.prefix(8)) of \(space.rawValue) did not round-trip")
    }

    @Test func aSpaceThatIsNotADisplaySpaceThrows() {
        #expect(throws: RenderError.self) { try DisplayTable(.linearSRGB) }
    }

    /// Seeded premultiplied pixels plus finite edges: alpha 0, 1 and subnormal, negatives, over 1.
    static func pixels() -> [RGBA] {
        var rng = SplitMix64(seed: 0x0D15_9A1A)
        var out: [RGBA] = (0..<4000).map { _ in
            let a = Float.random(in: 0...1, using: &rng)
            return RGBA(r: Float.random(in: 0...1, using: &rng) * a, g: Float.random(in: 0...1, using: &rng) * a,
                        b: Float.random(in: 0...1, using: &rng) * a, a: a)
        }
        out += (0...255).map { v in let f = Float(v) / 255; return RGBA(r: f, g: f, b: f, a: 1) }
        out += [RGBA(r: 0.5, g: 0.2, b: 0.1, a: 0), RGBA(r: 0, g: 0, b: 0, a: 0),
                RGBA(r: 1e-40, g: 0, b: 1e-40, a: 1e-40), RGBA(r: 0.2, g: 0.5, b: -1, a: 1),
                RGBA(r: 2, g: -0.0, b: 1.5, a: 1), RGBA(r: 3e38, g: -3e38, b: 0.25, a: 1),
                RGBA(r: 0.1, g: 0.2, b: 0.3, a: 0.5)]
        return out
    }

    static func buffer(_ pixels: [RGBA]) throws -> PixelBuffer {
        var buffer = try PixelBuffer(width: pixels.count, height: 1)
        for (x, p) in pixels.enumerated() { try buffer.setPixel(x: x, y: 0, p) }
        return buffer
    }
}
