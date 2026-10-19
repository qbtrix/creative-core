// GradientDitherTests.swift: fill-tools FT-6's acceptance. A dark ramp bands
// in 8-bit without the ordered dither and does not with it; the dither is a
// fixed matrix over both axes, so renders are equal and keep the mean value.
import CoreColor
import CoreRaster
import Testing

@Suite struct GradientDitherTests {
    /// 256 x 8, black to linear 0.01 (about 25 sRGB steps) along +x, so each
    /// 8-bit step spans about 10 px.
    private func darkRamp(dither: Bool) throws -> PixelBuffer {
        let stops = [RasterGradientStop(offset: 0, color: RGBA(r: 0, g: 0, b: 0, a: 1)),
                     RasterGradientStop(offset: 1, color: RGBA(r: 0.01, g: 0.01, b: 0.01, a: 1))]
        return try PixelBuffer.gradient(width: 256, height: 8, shape: .linear, from: Mask.Point(x: 0.5, y: 0.5),
                                        to: Mask.Point(x: 255.5, y: 0.5), stops: stops, space: .linear, dither: dither)
    }

    /// An 8 x 8 flat fill whose sRGB encode is 10.5 steps, half way between bytes.
    private func flat(dither: Bool) throws -> PixelBuffer {
        let v = Float(TransferCurve.decode(10.5 / 255))
        let c = RGBA(r: v, g: v, b: v, a: 1)
        return try PixelBuffer.gradient(width: 8, height: 8, shape: .linear, from: Mask.Point(x: 0, y: 0),
                                        to: Mask.Point(x: 8, y: 0), stops: [RasterGradientStop(offset: 0, color: c),
                                                                            RasterGradientStop(offset: 1, color: c)],
                                        space: .linear, dither: dither)
    }

    /// The red bytes of an 8-bit sRGB encode, row by row.
    private func reds(_ image: PixelBuffer) throws -> [[UInt8]] {
        let bytes = try image.rgba8()
        return (0..<image.height).map { y in (0..<image.width).map { x in bytes[(y * image.width + x) * 4] } }
    }

    /// The longest run of one value in `row`.
    private func longestRun(_ row: [UInt8]) -> Int {
        var best = 0, run = 0
        for (i, v) in row.enumerated() {
            run = i > 0 && row[i - 1] == v ? run + 1 : 1
            best = max(best, run)
        }
        return best
    }

    @Test
    func breaksBanding() throws {
        let off = try reds(try darkRamp(dither: false)), on = try reds(try darkRamp(dither: true))
        #expect(off.map(longestRun).max() ?? 0 > 12, "undithered ramp should band")
        for (y, row) in on.enumerated() {
            #expect(longestRun(row) <= 12, "row \(y): run \(longestRun(row))")
        }
        // The ramp still climbs: the dither only moves a pixel by one step.
        for (y, row) in on.enumerated() {
            for (x, v) in row.enumerated() { #expect(abs(Int(v) - Int(off[y][x])) <= 1, "(\(x), \(y))") }
        }
    }

    @Test
    func deterministic() throws {
        #expect(try darkRamp(dither: true) == darkRamp(dither: true))
        #expect(try darkRamp(dither: true) != darkRamp(dither: false))
    }

    /// Every row and every column of a flat half-step fill mixes both
    /// neighbouring bytes, half and half, so the matrix varies along x and y.
    @Test
    func usesBothAxes() throws {
        let rows = try reds(try flat(dither: true))
        let columns = (0..<8).map { x in rows.map { $0[x] } }
        for (k, line) in (rows + columns).enumerated() {
            #expect(Set(line) == [10, 11], "line \(k): \(line)")
            #expect(line.filter { $0 == 11 }.count == 4, "line \(k): \(line)")
        }
        #expect(Set(try reds(try flat(dither: false)).joined()).count == 1)
    }

    @Test
    func transparentStaysTransparent() throws {
        let clear = RGBA(r: 0, g: 0, b: 0, a: 0)
        let image = try PixelBuffer.gradient(width: 16, height: 16, shape: .radial, from: Mask.Point(x: 8, y: 8),
                                             to: Mask.Point(x: 16, y: 8),
                                             stops: [RasterGradientStop(offset: 0, color: clear),
                                                     RasterGradientStop(offset: 1, color: clear)])
        #expect(image.components.allSatisfy { $0 == 0 })
    }
}
