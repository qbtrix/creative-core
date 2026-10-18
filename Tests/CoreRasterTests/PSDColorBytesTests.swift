// PSD colour samples: the writer's bucketed sRGB encoder picks the same sample
// as a whole-table search (nearest decoded value, ties to the lower sample) at
// every bucket edge, around table entries and midpoints, for seeded values and
// out of range, at 8 and 16 bits, so the fast save writes the same file.
@testable import CoreRaster
import Testing

/// The first table entry at or above `value` by plain binary search, then the nearer of it and the one below.
private func searched(_ value: Float, _ table: [Float]) -> Int {
    var low = 0, high = table.count - 1
    while low < high {
        let mid = (low + high) / 2
        if table[mid] < value { low = mid + 1 } else { high = mid }
    }
    if low > 0, value - table[low - 1] <= table[low] - value { low -= 1 }
    return low
}

/// `value` and its `steps` neighbours below and above.
private func around(_ value: Float, _ steps: Int) -> [Float] {
    var below = [value], above: [Float] = []
    for _ in 0..<steps { below.append((below.last ?? value).nextDown); above.append((above.last ?? value).nextUp) }
    return below + above
}

@Suite struct PSDColorBytesTests {
    @Test(arguments: [PSDDepth.eight, .sixteen])
    func encoderMatchesTheTableScan(_ depth: PSDDepth) {
        let table = depth.linear, spans = depth.spans, n = PSD.spanCount
        var values: [Float] = [0, -0.0, 1, 1.5, -0.25, .nan, .infinity, -.infinity, .leastNonzeroMagnitude]
        for b in stride(from: 0, through: n, by: depth == .eight ? 1 : 7) { values += around(Float(b) / Float(n), 2) }
        for k in stride(from: 0, to: table.count, by: depth == .eight ? 1 : 97) {
            values += around(table[k], 2)
            if k > 0 { values += around((table[k - 1] + table[k]) / 2, 2) }
        }
        var rng = SplitMix64(seed: 0x50_5344)
        for _ in 0..<20_000 { values.append(.random(in: 0..<1, using: &rng)) }
        let wrong = values.filter { PSD.nearest($0, in: table, spans: spans) != searched($0, table) }
        #expect(wrong.isEmpty, "\(depth): \(wrong.prefix(5))")
    }

    @Test func planesHoldTheUnpremultipliedSamples() throws {
        let t = PSD.linear
        var buffer = try PixelBuffer(width: 3, height: 1)
        let pixels = [RGBA(r: t[200], g: t[17], b: t[255], a: 0.6), RGBA(r: t[51], g: 0, b: t[128], a: 1), RGBA(r: 0.3, g: 0.3, b: 0.3, a: 0)]
        for (x, p) in pixels.enumerated() { try buffer.setPixel(x: x, y: 0, p.premultiplied()) }
        #expect(PSDDepth.eight.colorPlanes(buffer) == [[200, 51, 0], [17, 0, 0], [255, 128, 0], [153, 255, 0]])
        #expect(PSDDepth.sixteen.colorPlanes(buffer)[3] == [0x99, 0x99, 0xFF, 0xFF, 0, 0])
    }
}
