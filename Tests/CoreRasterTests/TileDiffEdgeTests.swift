// TileDiffEdgeTests.swift: adversarial and boundary tests for TileDiff. Tile
// edges at and around multiples of tileSize, one-pixel-wide and one-pixel-tall
// buffers, an edit that touches every tile, undo and redo repeated and chained
// across successive edits, a diff applied to another buffer of the same size,
// and a seeded fuzz test of sparse single-component bit flips (including 0.0 to
// -0.0) where the kept tiles must be exactly those with a changed bit.
import CoreRaster
import Testing

/// True when every component of `a` and `b` has the same bit pattern.
private func sameBits(_ a: PixelBuffer, _ b: PixelBuffer) throws -> Bool {
    guard a.width == b.width, a.height == b.height else { return false }
    for y in 0..<a.height {
        for x in 0..<a.width {
            let p = try a.pixel(x: x, y: y), q = try b.pixel(x: x, y: y)
            let pb = [p.r.bitPattern, p.g.bitPattern, p.b.bitPattern, p.a.bitPattern]
            let qb = [q.r.bitPattern, q.g.bitPattern, q.b.bitPattern, q.a.bitPattern]
            if pb != qb { return false }
        }
    }
    return true
}

@Test func tileEdgesCountTheRightTiles() throws {
    let red = RGBA(r: 1, g: 0, b: 0, a: 1)
    // (width, height, x, y): one pixel on or next to a tile edge.
    let cases: [(Int, Int, Int, Int)] = [
        (256, 256, 255, 255), (257, 257, 256, 256), (512, 1, 511, 0),
        (1, 512, 0, 256), (1, 1, 0, 0), (700, 700, 699, 699), (513, 300, 512, 299),
    ]
    for (w, h, x, y) in cases {
        let before = try PixelBuffer(width: w, height: h)
        var after = before
        try after.setPixel(x: x, y: y, red)
        let diff = try TileDiff(before: before, after: after)
        #expect(diff.tileCount == 1, "\(w)x\(h) at (\(x), \(y))")
        #expect(diff.width == w && diff.height == h)
        var buffer = after
        try diff.undo(&buffer)
        #expect(try sameBits(buffer, before), "\(w)x\(h)")
    }
}

@Test func editTouchingEveryTileKeepsAllAndRoundTrips() throws {
    for (w, h) in [(1, 1), (257, 1), (1, 769), (600, 513), (1024, 256)] {
        let before = try PixelBuffer(width: w, height: h)
        let after = try PixelBuffer(width: w, height: h, fill: RGBA(r: 0.25, g: 0.5, b: 0.75, a: 1))
        let diff = try TileDiff(before: before, after: after)
        #expect(diff.tileCount == before.tileColumns * before.tileRows, "\(w)x\(h)")
        var buffer = after
        try diff.undo(&buffer)
        #expect(try sameBits(buffer, before))
        try diff.redo(&buffer)
        #expect(try sameBits(buffer, after))
    }
}

@Test func undoAndRedoAreIdempotentAndRedoFirstIsHarmless() throws {
    let before = try PixelBuffer(width: 300, height: 300, fill: RGBA(r: 0.1, g: 0.2, b: 0.3, a: 0.4))
    var after = before
    try after.setPixel(x: 280, y: 5, RGBA(r: 1, g: 1, b: 1, a: 1))
    let diff = try TileDiff(before: before, after: after)
    var buffer = after
    try diff.redo(&buffer)
    #expect(try sameBits(buffer, after))
    try diff.undo(&buffer)
    try diff.undo(&buffer)
    #expect(try sameBits(buffer, before))
    try diff.redo(&buffer)
    try diff.redo(&buffer)
    #expect(try sameBits(buffer, after))
}

@Test func emptyDiffLeavesAnySameSizeBufferAlone() throws {
    let base = try PixelBuffer(width: 400, height: 90)
    let diff = try TileDiff(before: base, after: base)
    #expect(diff.tileCount == 0)
    #expect(diff == (try TileDiff(before: base, after: base)))
    var other = try PixelBuffer(width: 400, height: 90, fill: RGBA(r: -1, g: 2, b: 0.5, a: 1))
    let original = other
    try diff.undo(&other)
    try diff.redo(&other)
    #expect(try sameBits(other, original))
}

@Test func diffOnlyWritesItsTilesIntoAnotherBuffer() throws {
    // Undo applied to a different same-size buffer replaces only the kept
    // tile; every other tile keeps that buffer's own contents.
    let before = try PixelBuffer(width: 512, height: 512)
    var after = before
    try after.setPixel(x: 300, y: 10, RGBA(r: 1, g: 0, b: 0, a: 1))
    let diff = try TileDiff(before: before, after: after)
    let gray = RGBA(r: 0.5, g: 0.5, b: 0.5, a: 1)
    var other = try PixelBuffer(width: 512, height: 512, fill: gray)
    try diff.undo(&other)
    #expect(try other.pixel(x: 300, y: 10) == .clear)
    #expect(try other.pixel(x: 256, y: 255) == .clear)
    #expect(try other.pixel(x: 255, y: 0) == gray)
    #expect(try other.pixel(x: 256, y: 256) == gray)
    #expect(try other.pixel(x: 511, y: 511) == gray)
}

@Test func chainedDiffsUnwindInReverseOrder() throws {
    var rng = SplitMix64(seed: 0x7D1F)
    let w = 333, h = 517
    var states = [try PixelBuffer(width: w, height: h, fill: randomPixel(&rng))]
    var diffs = [TileDiff]()
    for _ in 0..<6 {
        var next = states[states.count - 1]
        for _ in 0..<Int.random(in: 1...20, using: &rng) {
            try next.setPixel(x: Int.random(in: 0..<w, using: &rng), y: Int.random(in: 0..<h, using: &rng),
                              randomPixel(&rng))
        }
        diffs.append(try TileDiff(before: states[states.count - 1], after: next))
        states.append(next)
    }
    var buffer = states[states.count - 1]
    for i in stride(from: diffs.count - 1, through: 0, by: -1) {
        try diffs[i].undo(&buffer)
        #expect(try sameBits(buffer, states[i]), "undo to state \(i)")
    }
    for i in 0..<diffs.count {
        try diffs[i].redo(&buffer)
        #expect(try sameBits(buffer, states[i + 1]), "redo to state \(i + 1)")
    }
}

@Test func sizeMismatchesThrowForEveryAxisAndChangeNothing() throws {
    let base = try PixelBuffer(width: 256, height: 256)
    var after = base
    try after.setPixel(x: 0, y: 0, RGBA(r: 1, g: 1, b: 1, a: 1))
    let diff = try TileDiff(before: base, after: after)
    // Same tile grid (1x1) but another size, and the transposed size.
    for (w, h) in [(255, 256), (256, 255), (1, 1), (257, 256), (256, 257)] {
        let other = try PixelBuffer(width: w, height: h, fill: RGBA(r: 0.3, g: 0.3, b: 0.3, a: 1))
        #expect(throws: RasterError.self) { try TileDiff(before: base, after: other) }
        #expect(throws: RasterError.self) { try TileDiff(before: other, after: base) }
        var target = other
        #expect(throws: RasterError.self) { try diff.undo(&target) }
        #expect(throws: RasterError.self) { try diff.redo(&target) }
        #expect(try sameBits(target, other), "\(w)x\(h)")
    }
    let wide = try PixelBuffer(width: 300, height: 200), tall = try PixelBuffer(width: 200, height: 300)
    #expect(throws: RasterError.self) { try TileDiff(before: wide, after: tall) }
}

@Test func fuzzSparseBitFlipsKeepExactlyTheChangedTiles() throws {
    var rng = SplitMix64(seed: 0xB17F_1195)
    let edgeValues: [Float] = [0, -0.0, .leastNonzeroMagnitude, -.leastNonzeroMagnitude,
                               .greatestFiniteMagnitude, -.greatestFiniteMagnitude, 1, 1.0000001]
    for _ in 0..<40 {
        let w = Int.random(in: 1...800, using: &rng)
        let h = Int.random(in: 1...800, using: &rng)
        let before = try PixelBuffer(width: w, height: h)
        var after = before
        var changed = Set<[Int]>()
        for _ in 0..<Int.random(in: 0...8, using: &rng) {
            let x = Int.random(in: 0..<w, using: &rng), y = Int.random(in: 0..<h, using: &rng)
            var p = try after.pixel(x: x, y: y)
            let v = edgeValues[Int.random(in: 0..<edgeValues.count, using: &rng)]
            switch Int.random(in: 0..<4, using: &rng) {
            case 0: p.r = v
            case 1: p.g = v
            case 2: p.b = v
            default: p.a = v
            }
            try after.setPixel(x: x, y: y, p)
        }
        // The expected set is every tile holding a pixel whose bits changed.
        for row in 0..<before.tileRows {
            for column in 0..<before.tileColumns where !(try sameBits(
                try before.tile(column: column, row: row), try after.tile(column: column, row: row))) {
                changed.insert([column, row])
            }
        }
        let diff = try TileDiff(before: before, after: after)
        #expect(diff.tileCount == changed.count, "\(w)x\(h)")
        var buffer = after
        try diff.undo(&buffer)
        #expect(try sameBits(buffer, before), "undo \(w)x\(h)")
        try diff.redo(&buffer)
        #expect(try sameBits(buffer, after), "redo \(w)x\(h)")
    }
}
