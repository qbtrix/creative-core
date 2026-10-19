// FloodFill.swift: the flood-fill mask behind the paint bucket and the magic
// wand (fill-tools). A scanline fill with an explicit stack of seeds (never
// recursion) over a visited bitset; global mode tests every pixel. A pixel
// matches when its OKLab distance from the seed (alpha as a fourth axis) is at
// most the tolerance. With anti-aliasing, a rejected pixel next to a taken one
// gets a one-pixel soft edge `1 - (d - t) / t`. Extra memory past the output
// mask is bounded on any image: two bitsets (taken, queued: 1 bit per pixel
// each) and a seed stack of at most one UInt32 per 16 pixels (or 65 536),
// about 0.5 bytes per pixel in all. Seeds a full stack drops stay queued in
// the bitset and later sweeps of it pick them up.
import CoreColor

/// Which neighbours a contiguous flood fill steps to: the four edge
/// neighbours, or all eight including the diagonals.
public enum Connectivity: Hashable, Sendable {
    /// Left, right, up and down only: regions that touch at a corner stay apart.
    case four
    /// The four edge neighbours plus the four diagonals: a corner joins regions.
    case eight
}

extension PixelBuffer {
    /// A mask of the pixels a fill from `seed` takes.
    ///
    /// - Parameters:
    ///   - seed: the starting pixel; must lie inside the buffer
    ///     (`0..<width`, `0..<height`), or the call throws.
    ///   - tolerance: `.exact`, or `.within(t)` with `t` in 0...1, an OKLab
    ///     distance of the straight colours (alpha as a fourth axis) from the
    ///     seed's colour (`FillColor`).
    ///   - contiguous: `true` takes only pixels connected to the seed;
    ///     `false` takes every matching pixel in the buffer.
    ///   - connectivity: the neighbours a contiguous fill steps to.
    ///   - antiAlias: `true` gives the rejected pixels next to taken ones (by
    ///     `connectivity`) a one-pixel soft edge of coverage `1 − (d − t) / t`,
    ///     clamped to 0...1, so it falls to 0 at distance 2t. Ignored for
    ///     `.exact` and `.within(0)`, which always give a hard mask.
    /// - Returns: a mask the size of the buffer, coverage in 0...1.
    /// - Throws: `RasterError.invalid` for a seed outside the buffer, a
    ///   tolerance outside 0...1, or a pixel the fill reads that is not finite
    ///   once unpremultiplied (so has no OKLab value); the message names it.
    public func floodMask(from seed: (x: Int, y: Int), tolerance: FillTolerance, contiguous: Bool = true,
                          connectivity: Connectivity = .four, antiAlias: Bool = true) throws -> Mask {
        try floodMask(from: seed, tolerance: tolerance, contiguous: contiguous, connectivity: connectivity,
                      antiAlias: antiAlias, pendingLimit: nil)
    }

    /// `floodMask` with the seed stack capped at `pendingLimit` entries
    /// (nil: the larger of 65 536 and one per 16 pixels), so tests can force
    /// the sweeps that pick up seeds a full stack dropped. Same mask for any cap.
    func floodMask(from seed: (x: Int, y: Int), tolerance: FillTolerance, contiguous: Bool,
                   connectivity: Connectivity, antiAlias: Bool, pendingLimit: Int?) throws -> Mask {
        guard (0..<width).contains(seed.x), (0..<height).contains(seed.y) else {
            throw RasterError.invalid("flood seed (\(seed.x), \(seed.y)) is outside the \(width)x\(height) buffer")
        }
        let limit: Double
        switch tolerance {
        case .exact: limit = 0
        case .within(let t):
            guard (0...1).contains(t) else { throw RasterError.invalid("flood tolerance \(t) is outside 0...1") }
            limit = Double(t)
        }
        let reach = connectivity == .eight ? 1 : 0
        let (w, h) = (width, height)
        var coverage = [Float](repeating: 0, count: w * h)
        var taken = [UInt64](repeating: 0, count: (w * h + 63) / 64)
        try components.withUnsafeBufferPointer { pixels in
            let match = try FloodMatch(pixels, width: w, seed: seed.y * w + seed.x, limit: limit)
            func isTaken(_ i: Int) -> Bool { taken[i >> 6] & (1 << UInt64(i & 63)) != 0 }
            func take(_ i: Int) {
                taken[i >> 6] |= 1 << UInt64(i & 63)
                coverage[i] = 1
            }
            if !contiguous {
                for i in 0..<(w * h) { if try match.accepts(i) { take(i) } }
            } else {
                // Each stack entry is a pixel known to match, marked in `queued`
                // when found so it is never pushed twice. The stack holds at
                // most `limit` entries (UInt32: maxPixels fits); a pixel found
                // while it is full stays only in `queued`, and sweeps of
                // `queued` pick those up until a sweep drops none.
                let limit = max(pendingLimit ?? max(1 << 16, w * h / 16), 1)
                var queued = [UInt64](repeating: 0, count: taken.count)
                var stack = [UInt32]()
                stack.reserveCapacity(min(limit, w * h))
                var dropped = false
                func enqueue(_ i: Int) {
                    queued[i >> 6] |= 1 << UInt64(i & 63)
                    if stack.count < limit { stack.append(UInt32(truncatingIfNeeded: i)) } else { dropped = true }
                }
                func drain() throws {
                    while let entry = stack.popLast() {
                        let start = Int(entry)
                        guard !isTaken(start) else { continue }
                        let y = start / w, row = y * w
                        var (left, right) = (start - row, start - row)
                        while left > 0, !isTaken(row + left - 1), try match.accepts(row + left - 1) { left -= 1 }
                        while right < w - 1, !isTaken(row + right + 1), try match.accepts(row + right + 1) { right += 1 }
                        for x in left...right { take(row + x) }
                        let (lo, hi) = (max(left - reach, 0), min(right + reach, w - 1))
                        for ny in [y - 1, y + 1] where (0..<h).contains(ny) {
                            var inRun = false
                            for x in lo...hi {
                                let i = ny * w + x
                                let open = try !isTaken(i) && match.accepts(i)
                                if open, !inRun, queued[i >> 6] & (1 << UInt64(i & 63)) == 0 { enqueue(i) }
                                inRun = open
                            }
                        }
                    }
                }
                enqueue(seed.y * w + seed.x)
                try drain()
                while dropped {
                    dropped = false
                    for word in queued.indices {
                        var bits = queued[word] & ~taken[word]
                        while bits != 0 {
                            stack.append(UInt32(truncatingIfNeeded: word << 6 | bits.trailingZeroBitCount))
                            bits &= bits - 1
                            try drain()
                        }
                    }
                }
            }
            if antiAlias, limit > 0 {
                for y in 0..<h {
                    for x in 0..<w where !isTaken(y * w + x) {
                        var touches = false
                        for dy in -1...1 where (0..<h).contains(y + dy) {
                            for dx in -1...1 where (0..<w).contains(x + dx) && (reach == 1 || dx == 0 || dy == 0) {
                                touches = touches || isTaken((y + dy) * w + x + dx)
                            }
                        }
                        guard touches else { continue }
                        let d = try match.distance(y * w + x)
                        coverage[y * w + x] = Float(min(max(1 - (d - limit) / limit, 0), 1))
                    }
                }
            }
        }
        return Mask(checkedWidth: w, height: h, storage: coverage)
    }
}

/// The seed's colour and the tolerance, for testing pixels of one buffer's
/// premultiplied components.
private struct FloodMatch {
    let pixels: UnsafeBufferPointer<Float>
    let width: Int
    let seed: RGBA
    let seedColor: FillColor
    let limit: Double

    init(_ pixels: UnsafeBufferPointer<Float>, width: Int, seed index: Int, limit: Double) throws {
        self.pixels = pixels
        self.width = width
        self.limit = limit
        seed = Self.color(pixels, index)
        seedColor = try FillColor(seed, what: "flood fill: pixel (\(index % width), \(index / width))")
    }

    private static func color(_ pixels: UnsafeBufferPointer<Float>, _ i: Int) -> RGBA {
        RGBA(r: pixels[4 * i], g: pixels[4 * i + 1], b: pixels[4 * i + 2], a: pixels[4 * i + 3])
    }

    /// The `FillColor` distance of pixel `i` from the seed.
    func distance(_ i: Int) throws -> Double {
        let c = Self.color(pixels, i)
        guard c != seed else { return 0 }
        return try FillColor(c, what: "flood fill: pixel (\(i % width), \(i / width))").distance(to: seedColor)
    }

    /// Whether pixel `i` is within the tolerance: `d <= t`, so `.within(0)` takes exact matches.
    func accepts(_ i: Int) throws -> Bool { try distance(i) <= limit }
}
