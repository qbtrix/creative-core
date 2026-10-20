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
        try floodMaskAndScratch(from: seed, tolerance: tolerance, contiguous: contiguous, connectivity: connectivity,
                                antiAlias: antiAlias, pendingLimit: nil).mask
    }

    /// `floodMask` with the seed stack capped at `pendingLimit` entries
    /// (nil: the larger of 65 536 and one per 16 pixels), so tests can force
    /// the sweeps that pick up seeds a full stack dropped. Same mask for any
    /// cap. `scratchBytes` is what the fill allocated past the mask: the
    /// bitset words times 8 plus the seed stack's capacity times 4.
    func floodMaskAndScratch(from seed: (x: Int, y: Int), tolerance: FillTolerance, contiguous: Bool,
                             connectivity: Connectivity, antiAlias: Bool,
                             pendingLimit: Int?) throws -> (mask: Mask, scratchBytes: Int) {
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
        let (w, h) = (width, height), n = w * h
        // Each stack entry is a pixel known to match, marked in `queued` when
        // found so it is never pushed twice. The stack is allocated once at
        // its cap (UInt32: maxPixels fits); a pixel found while it is full
        // stays only in `queued`, and sweeps of `queued` pick those up.
        let cap = contiguous ? min(max(pendingLimit ?? max(1 << 16, n / 16), 1), n) : 0
        let words = (n + 63) / 64
        let taken = UnsafeMutableBufferPointer<UInt64>.allocate(capacity: words)
        let queued = UnsafeMutableBufferPointer<UInt64>.allocate(capacity: contiguous ? words : 0)
        let stack = UnsafeMutableBufferPointer<UInt32>.allocate(capacity: cap)
        defer { taken.deallocate(); queued.deallocate(); stack.deallocate() }
        taken.initialize(repeating: 0)
        queued.initialize(repeating: 0)
        let coverage = try [Float](unsafeUninitializedCapacity: n) { cover, count in
            cover.initialize(repeating: 0)
            count = n
            try components.withUnsafeBufferPointer { pixels in
                let match = try FloodMatch(pixels, width: w, seed: seed.y * w + seed.x, limit: limit)
                var fill = FloodScan(match: match, coverage: cover, taken: taken, queued: queued, stack: stack,
                                     w: w, h: h, reach: reach)
                if !contiguous {
                    for i in 0..<n where try fill.match.accepts(i) { fill.take(i) }
                } else {
                    try fill.fill(from: seed.y * w + seed.x)
                }
                if antiAlias, limit > 0 { try fill.softEdge(limit: limit) }
            }
        }
        let scratchBytes = (taken.count + queued.count) * 8 + stack.count * 4
        return (Mask(checkedWidth: w, height: h, storage: coverage), scratchBytes)
    }
}

/// One fill's pointers into its mask, bitsets and seed stack, and the
/// scanline walk over them.
private struct FloodScan {
    var match: FloodMatch
    let coverage: UnsafeMutableBufferPointer<Float>
    let taken: UnsafeMutableBufferPointer<UInt64>
    let queued: UnsafeMutableBufferPointer<UInt64>
    let stack: UnsafeMutableBufferPointer<UInt32>
    let w: Int, h: Int, reach: Int
    var pending = 0
    var dropped = false

    func isTaken(_ i: Int) -> Bool { taken[i >> 6] & (1 << UInt64(i & 63)) != 0 }
    func isQueued(_ i: Int) -> Bool { queued[i >> 6] & (1 << UInt64(i & 63)) != 0 }
    func take(_ i: Int) {
        taken[i >> 6] |= 1 << UInt64(i & 63)
        coverage[i] = 1
    }

    /// Whether pixel `i` is untaken and matches; a queued pixel is known to.
    mutating func open(_ i: Int) throws -> Bool { try !isTaken(i) && (isQueued(i) || match.accepts(i)) }

    mutating func enqueue(_ i: Int) {
        queued[i >> 6] |= 1 << UInt64(i & 63)
        if pending < stack.count {
            stack[pending] = UInt32(truncatingIfNeeded: i)
            pending += 1
        } else {
            dropped = true
        }
    }

    /// The contiguous fill from pixel `seed`: drain the stack, then sweep
    /// `queued` for dropped seeds until a sweep drops none.
    mutating func fill(from seed: Int) throws {
        enqueue(seed)
        try drain()
        while dropped {
            dropped = false
            for word in queued.indices {
                var bits = queued[word] & ~taken[word]
                while bits != 0 {
                    enqueue(word << 6 | bits.trailingZeroBitCount)
                    bits &= bits - 1
                    try drain()
                }
            }
        }
    }

    mutating func drain() throws {
        while pending > 0 {
            pending -= 1
            let start = Int(stack[pending])
            guard !isTaken(start) else { continue }
            let y = start / w, row = y * w
            var (left, right) = (start - row, start - row)
            while left > 0, try open(row + left - 1) { left -= 1 }
            while right < w - 1, try open(row + right + 1) { right += 1 }
            for x in left...right { take(row + x) }
            let (lo, hi) = (max(left - reach, 0), min(right + reach, w - 1))
            if y > 0 { try scan(row: row - w, lo, hi) }
            if y < h - 1 { try scan(row: row + w, lo, hi) }
        }
    }

    /// Queues the first pixel of each open run in `row + lo...row + hi`.
    mutating func scan(row: Int, _ lo: Int, _ hi: Int) throws {
        var inRun = false
        for x in lo...hi {
            let i = row + x
            let isOpen = try open(i)
            if isOpen, !inRun, !isQueued(i) { enqueue(i) }
            inRun = isOpen
        }
    }

    /// Gives each untaken pixel next to a taken one coverage `1 - (d - t) / t`.
    mutating func softEdge(limit: Double) throws {
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

/// The seed's colour and the tolerance, for testing pixels of one buffer's
/// premultiplied components. The last colour measured and its distance are
/// kept (first the seed's, at 0), so a flat region converts its colour once.
private struct FloodMatch {
    let pixels: UnsafeBufferPointer<Float>
    let width: Int
    let seedColor: FillColor
    let limit: Double
    private var last: RGBA
    private var lastDistance = 0.0

    init(_ pixels: UnsafeBufferPointer<Float>, width: Int, seed index: Int, limit: Double) throws {
        self.pixels = pixels
        self.width = width
        self.limit = limit
        last = Self.color(pixels, index)
        seedColor = try FillColor(last, what: "flood fill: pixel (\(index % width), \(index / width))")
    }

    private static func color(_ pixels: UnsafeBufferPointer<Float>, _ i: Int) -> RGBA {
        RGBA(r: pixels[4 * i], g: pixels[4 * i + 1], b: pixels[4 * i + 2], a: pixels[4 * i + 3])
    }

    /// The `FillColor` distance of pixel `i` from the seed.
    mutating func distance(_ i: Int) throws -> Double {
        let c = Self.color(pixels, i)
        guard c != last else { return lastDistance }
        lastDistance = try FillColor(c, what: "flood fill: pixel (\(i % width), \(i / width))").distance(to: seedColor)
        last = c
        return lastDistance
    }

    /// Whether pixel `i` is within the tolerance: `d <= t`, so `.within(0)` takes exact matches.
    mutating func accepts(_ i: Int) throws -> Bool { try distance(i) <= limit }
}
