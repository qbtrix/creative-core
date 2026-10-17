// ResampleTableTests.swift: the Metal resample kernel's tap tables (MB-8) hold normalised weights and clamped
// indices, keep a same-length axis as the identity, reject bad lengths, and give CoreRaster's `resized` on a line.
import CoreRaster
import CoreRender
import Testing

@Suite struct ResampleTableTests {
    private static let lengths = [(1, 1), (1, 7), (7, 1), (9, 13), (13, 9), (300, 37), (37, 301), (256, 255), (5, 5)]

    @Test func everyOutputsWeightsSumToOneOverClampedTaps() throws {
        for filter in [ResampleFilter.bilinear, .lanczos3] {
            for (length, newLength) in Self.lengths {
                let table = try ResampleTable(length: length, newLength: newLength, filter: filter)
                #expect(table.offsets.count == newLength + 1 && table.offsets.first == 0)
                #expect(table.offsets.last.map(Int.init) == table.indices.count && table.weights.count == table.indices.count)
                for i in 0..<newLength {
                    let (start, end) = (Int(table.offsets[i]), Int(table.offsets[i + 1]))
                    let sum = table.weights[start..<end].reduce(0, +)
                    #expect(end > start && abs(sum - 1) < 1e-5, "\(filter) \(length)->\(newLength) output \(i) sums to \(sum)")
                }
                #expect(table.indices.allSatisfy { $0 >= 0 && Int($0) < length }, "taps clamp to the edge")
            }
        }
    }

    @Test func sameLengthIsTheIdentityAndBadLengthsThrow() throws {
        for filter in [ResampleFilter.bilinear, .lanczos3] {
            let table = try ResampleTable(length: 6, newLength: 6, filter: filter)
            #expect(table.isIdentity && table.indices == [0, 1, 2, 3, 4, 5] && table.weights == Array(repeating: 1, count: 6))
        }
        #expect(try !ResampleTable(length: 6, newLength: 7, filter: .bilinear).isIdentity)
        for (length, newLength) in [(0, 4), (4, 0), (-1, 3), (Int(Int32.max) + 1, 2), (2, Int.max)] {
            #expect(throws: RenderError.self) { try ResampleTable(length: length, newLength: newLength, filter: .lanczos3) }
        }
    }

    /// One row through the table equals CoreRaster's `resized` of a one-pixel-high buffer, for both filters up and down.
    @Test func matchesCoreRasterOnALine() throws {
        var rng = ParityRandom(seed: 0x5E5A)
        for filter in [ResampleFilter.bilinear, .lanczos3] {
            for (length, newLength) in Self.lengths {
                var buffer = try PixelBuffer(width: length, height: 1)
                for x in 0..<length {
                    let a = Float.random(in: 0...1, using: &rng)
                    try buffer.setPixel(x: x, y: 0, RGBA(r: Float.random(in: 0...a, using: &rng), g: a / 2, b: 0, a: a))
                }
                let want = try buffer.resized(width: newLength, height: 1, filter: filter)
                let table = try ResampleTable(length: length, newLength: newLength, filter: filter)
                let pixels = try (0..<length).map { try buffer.pixel(x: $0, y: 0) }
                let reds = table.apply(pixels.map(\.r)), alphas = table.apply(pixels.map(\.a))
                for i in 0..<newLength {
                    let p = try want.pixel(x: i, y: 0)
                    #expect(abs(reds[i] - p.r) < 1e-5 && abs(alphas[i] - p.a) < 1e-5, "\(filter) \(length)->\(newLength) pixel \(i)")
                }
            }
        }
        #expect(try ResampleTable(length: 3, newLength: 2, filter: .bilinear).apply([1, 2]).isEmpty)
    }
}
