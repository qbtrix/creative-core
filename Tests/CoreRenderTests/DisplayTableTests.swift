// DisplayTableTests.swift: the Float thresholds the Metal display kernel reads, and `encode`, its
// Swift mirror: each threshold is the first Float at its level by `DisplayTransfer` itself; sRGB
// equals `PixelBuffer.rgba8` exactly, P3 within one byte; every byte per channel survives half
// storage in both spaces; NaN, infinity and short tables stay in range; other spaces throw.
import CoreColor
import CoreRaster
import CoreRender
import Testing

@Suite struct DisplayTableTests {
    @Test func everyThresholdIsTheFirstFloatAtItsLevel() throws {
        let t = try DisplayTable(.sRGB).thresholds, transfer = try DisplayTransfer(.sRGB)
        #expect(t.count == 2 * DisplayTable.levels)
        for k in 1...DisplayTable.levels {
            let curve = t[k - 1], alpha = t[DisplayTable.alphaBase + k - 1]
            #expect(Int(transfer.encode(Color3(Double(curve), 0, 0)).0) == k)
            #expect(Int(transfer.encode(Color3(Double(curve.nextDown), 0, 0)).0) == k - 1)
            #expect(Int(DisplayTransfer.byte(Double(alpha))) == k && Int(DisplayTransfer.byte(Double(alpha.nextDown))) == k - 1)
            #expect(Int(DisplayTable.level(curve, t, base: 0)) == k && Int(DisplayTable.level(curve.nextDown, t, base: 0)) == k - 1)
            #expect(Int(DisplayTable.level(alpha, t, base: DisplayTable.alphaBase)) == k)
        }
        #expect(DisplayTable.level(.nan, t, base: 0) == 0 && DisplayTable.level(.infinity, t, base: 0) == 255)
        #expect(DisplayTable.level(1, [], base: 0) == 0 && DisplayTable.level(1, t, base: DisplayTable.alphaBase + 1) == 0)
    }

    @Test(arguments: [ColorSpace.sRGB, .displayP3])
    func encodeMatchesTheCPUBytes(_ space: ColorSpace) throws {
        var rng = SplitMix64(seed: 0x0D15_9A1A)
        var pixels: [RGBA] = (0..<4000).map { _ in
            let a = Float.random(in: 0...1, using: &rng)
            return RGBA(r: .random(in: 0...a, using: &rng), g: .random(in: 0...a, using: &rng), b: .random(in: 0...a, using: &rng), a: a)
        }
        pixels += [RGBA(r: 0.5, g: 0.2, b: 0.1, a: 0), RGBA(r: 1e-40, g: 0, b: 1e-40, a: 1e-40),
                   RGBA(r: 2, g: -0.0, b: -1, a: 1), RGBA(r: 3e38, g: -3e38, b: 0.25, a: 1)]
        var buffer = try PixelBuffer(width: pixels.count, height: 1)
        for (x, p) in pixels.enumerated() { try buffer.setPixel(x: x, y: 0, p) }
        let expected = try buffer.rgba8(colorSpace: space), table = try DisplayTable(space)
        let actual = pixels.flatMap { table.encode($0) }
        #expect((table.matrix == nil) == (space == .sRGB))
        if space == .sRGB { #expect(actual == expected) }
        #expect(zip(actual, expected).allSatisfy { abs(Int($0) - Int($1)) <= 1 } && actual.count == expected.count)
    }

    /// Texture values are clamped finite, but NaN still follows `rgba8`'s rule: it encodes as 0.
    @Test func nonFiniteValuesStayInRange() throws {
        let table = try DisplayTable(.sRGB)
        #expect(table.encode(RGBA(r: .nan, g: .infinity, b: -.infinity, a: 1)) == [0, 255, 0, 255])
        #expect(table.encode(RGBA(r: 0.3, g: 0.3, b: 0.3, a: .nan)) == [0, 0, 0, 0])
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
        let table = try DisplayTable(space), half = { (v: Float) in HalfFloat.decode(HalfFloat.encode(v)) }
        var encoded: [UInt8] = []
        for i in 0..<(256 * 4) {
            let p = try buffer.pixel(x: i % 256, y: i / 256)
            encoded += table.encode(RGBA(r: half(p.r), g: half(p.g), b: half(p.b), a: half(p.a)))
        }
        // Alpha 0 carries no color, so (255, 255, 255, 0) comes back as all zeros, as the CPU encodes it.
        bytes.replaceSubrange((3 * 256 * 4)..<(3 * 256 * 4 + 4), with: [0, 0, 0, 0])
        #expect(encoded == bytes)
    }

    @Test func aSpaceThatIsNotADisplaySpaceThrows() {
        #expect(throws: RenderError.self) { try DisplayTable(.linearSRGB) }
    }
}
