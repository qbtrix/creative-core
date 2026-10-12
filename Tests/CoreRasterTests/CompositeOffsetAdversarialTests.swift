// CompositeOffsetAdversarialTests.swift: composite(_:onto:x:y:mode:opacity:)
// beyond the acceptance test. Offsets one pixel either side of every edge,
// offsets near Int.min and Int.max with wide sources, a source larger than the
// backdrop, a seeded fuzz of sizes and offsets checked against an independent
// per-pixel placement, splitting the source into pieces, a transparent source
// and opacity 0 at any offset, and extreme pixel values that must throw a
// RasterError instead of crashing.
import CoreRaster
import Testing

/// An opaque buffer whose every pixel encodes its own coordinate (plus `tag`),
/// so a misplaced or flipped pixel shows up as a wrong value.
private func coordinateBuffer(_ w: Int, _ h: Int, tag: Float) throws -> PixelBuffer {
    var buffer = try PixelBuffer(width: w, height: h)
    for y in 0..<h {
        for x in 0..<w {
            try buffer.setPixel(x: x, y: y, RGBA(r: Float(x), g: Float(y), b: tag, a: 1))
        }
    }
    return buffer
}

private func randomBuffer(_ w: Int, _ h: Int, _ rng: inout SplitMix64) throws -> PixelBuffer {
    var buffer = try PixelBuffer(width: w, height: h)
    for y in 0..<h {
        for x in 0..<w {
            try buffer.setPixel(x: x, y: y, randomPixel(&rng).premultiplied())
        }
    }
    return buffer
}

/// The columns `start..<start + count` of `buffer`, all rows.
private func columns(_ buffer: PixelBuffer, _ start: Int, _ count: Int) throws -> PixelBuffer {
    var out = try PixelBuffer(width: count, height: buffer.height)
    for y in 0..<buffer.height {
        for x in 0..<count {
            try out.setPixel(x: x, y: y, buffer.pixel(x: start + x, y: y))
        }
    }
    return out
}

/// Checks that an opaque `.normal` composite at (x, y) copied exactly the
/// overlapping source pixels and left every other backdrop pixel alone.
/// Coordinates are computed with overflow-checked math, so extreme offsets
/// are judged without trapping.
private func expectPlaced(_ out: PixelBuffer, source: PixelBuffer, backdrop: PixelBuffer,
                          x: Int, y: Int) throws {
    #expect(out.width == backdrop.width && out.height == backdrop.height)
    for by in 0..<backdrop.height {
        for bx in 0..<backdrop.width {
            let (sx, ox) = bx.subtractingReportingOverflow(x)
            let (sy, oy) = by.subtractingReportingOverflow(y)
            let inside = !ox && !oy && (0..<source.width).contains(sx) && (0..<source.height).contains(sy)
            let want = inside ? try source.pixel(x: sx, y: sy) : try backdrop.pixel(x: bx, y: by)
            #expect(try out.pixel(x: bx, y: by) == want, "(\(bx), \(by)) at offset (\(x), \(y))")
        }
    }
}

@Test func offsetsOnePixelEitherSideOfEveryEdge() throws {
    let backdrop = try coordinateBuffer(5, 3, tag: 0)
    let source = try coordinateBuffer(2, 2, tag: 1)
    // One column or row overlapping, then none.
    let cases = [(4, 0), (5, 0), (-1, 0), (-2, 0), (0, 2), (0, 3), (0, -1), (0, -2),
                 (4, 2), (5, 3), (-1, -1), (-2, -2), (4, -1), (-1, 2)]
    for (x, y) in cases {
        let out = try composite(source, onto: backdrop, x: x, y: y, mode: .normal, opacity: 1)
        try expectPlaced(out, source: source, backdrop: backdrop, x: x, y: y)
    }
}

@Test func extremeOffsetsNeverOverflow() throws {
    let backdrop = try coordinateBuffer(4, 4, tag: 0)
    let wide = try coordinateBuffer(100_000, 1, tag: 1)
    let tall = try coordinateBuffer(1, 100_000, tag: 1)
    let near = [Int.min, Int.min + 1, -Int.max, -100_000, -99_999, Int.max - 1, Int.max]
    for v in near {
        for (x, y) in [(v, 0), (0, v), (v, v)] {
            for source in [wide, tall] {
                let out = try composite(source, onto: backdrop, x: x, y: y, mode: .normal, opacity: 1)
                try expectPlaced(out, source: source, backdrop: backdrop, x: x, y: y)
            }
        }
    }
}

@Test func sourceLargerThanTheBackdropCoversItFromInside() throws {
    let backdrop = try coordinateBuffer(3, 2, tag: 0)
    let source = try coordinateBuffer(9, 7, tag: 1)
    for (x, y) in [(-3, -2), (-6, -5), (0, 0), (-1, -4)] {
        let out = try composite(source, onto: backdrop, x: x, y: y, mode: .normal, opacity: 1)
        try expectPlaced(out, source: source, backdrop: backdrop, x: x, y: y)
    }
}

@Test func fuzzedSizesAndOffsetsPlaceEveryPixelExactly() throws {
    var rng = SplitMix64(seed: 0x181_0FF5E7)
    for _ in 0..<300 {
        let backdrop = try coordinateBuffer(.random(in: 1...9, using: &rng), .random(in: 1...9, using: &rng), tag: 0)
        let source = try coordinateBuffer(.random(in: 1...12, using: &rng), .random(in: 1...12, using: &rng), tag: 1)
        let pick: (inout SplitMix64) -> Int = { rng in
            switch Int.random(in: 0..<4, using: &rng) {
            case 0: return Int.random(in: Int.min...Int.max, using: &rng)
            case 1: return [Int.min, Int.max, -Int.max, Int.max - 1][Int.random(in: 0..<4, using: &rng)]
            default: return Int.random(in: -14...14, using: &rng)
            }
        }
        let x = pick(&rng)
        let y = pick(&rng)
        let out = try composite(source, onto: backdrop, x: x, y: y, mode: .normal, opacity: 1)
        try expectPlaced(out, source: source, backdrop: backdrop, x: x, y: y)
    }
}

@Test func splittingTheSourceIntoColumnsGivesTheSameResult() throws {
    var rng = SplitMix64(seed: 18101)
    for _ in 0..<40 {
        let backdrop = try randomBuffer(.random(in: 1...7, using: &rng), .random(in: 1...7, using: &rng), &rng)
        let source = try randomBuffer(.random(in: 2...8, using: &rng), .random(in: 1...8, using: &rng), &rng)
        let split = Int.random(in: 1..<source.width, using: &rng)
        let x = Int.random(in: -9...9, using: &rng)
        let y = Int.random(in: -9...9, using: &rng)
        let opacity = Float.random(in: 0...1, using: &rng)
        let left = try columns(source, 0, split)
        let right = try columns(source, split, source.width - split)
        for mode in BlendMode.allCases {
            let whole = try composite(source, onto: backdrop, x: x, y: y, mode: mode, opacity: opacity)
            let halves = try composite(right, onto: composite(left, onto: backdrop, x: x, y: y, mode: mode, opacity: opacity),
                                       x: x + split, y: y, mode: mode, opacity: opacity)
            #expect(whole == halves, "\(mode) split \(split) at (\(x), \(y))")
        }
    }
}

@Test func transparentSourceAndZeroOpacityLeaveTheBackdropAtAnyOffset() throws {
    var rng = SplitMix64(seed: 18102)
    for _ in 0..<30 {
        let backdrop = try randomBuffer(.random(in: 1...6, using: &rng), .random(in: 1...6, using: &rng), &rng)
        let clear = try PixelBuffer(width: .random(in: 1...6, using: &rng), height: .random(in: 1...6, using: &rng))
        let opaque = try randomBuffer(clear.width, clear.height, &rng)
        let x = Int.random(in: -7...7, using: &rng)
        let y = Int.random(in: -7...7, using: &rng)
        for mode in BlendMode.allCases {
            #expect(try composite(clear, onto: backdrop, x: x, y: y, mode: mode, opacity: 1) == backdrop, "\(mode)")
            #expect(try composite(opaque, onto: backdrop, x: x, y: y, mode: mode, opacity: 0) == backdrop, "\(mode)")
        }
    }
}

@Test func sameSizeCallStillRejectsSmallerAndLargerSources() throws {
    let backdrop = try PixelBuffer(width: 4, height: 4)
    for (w, h) in [(2, 2), (4, 3), (3, 4), (5, 4), (4, 5), (1, 1)] {
        let source = try PixelBuffer(width: w, height: h)
        #expect(throws: RasterError.self) { try composite(source, onto: backdrop, mode: .normal, opacity: 1) }
        // The offset call accepts the same pair.
        #expect(try composite(source, onto: backdrop, x: 0, y: 0, mode: .normal, opacity: 1) == backdrop)
    }
}

@Test func overflowingPixelsThrowInsideTheOverlapOnly() throws {
    let huge = Float.greatestFiniteMagnitude
    let backdrop = try PixelBuffer(width: 4, height: 4, fill: RGBA(r: huge, g: huge, b: huge, a: 1))
    let source = try PixelBuffer(width: 2, height: 2, fill: RGBA(r: huge, g: huge, b: huge, a: 1))
    // Screen gives cb + cs - cb * cs, which is not finite for these values.
    #expect(throws: RasterError.self) { try composite(source, onto: backdrop, x: 3, y: 3, mode: .screen, opacity: 1) }
    #expect(throws: RasterError.self) { try composite(source, onto: backdrop, x: -1, y: -1, mode: .screen, opacity: 1) }
    // No overlap, so nothing is blended and nothing throws.
    #expect(try composite(source, onto: backdrop, x: 4, y: 0, mode: .screen, opacity: 1) == backdrop)
    #expect(try composite(source, onto: backdrop, x: -2, y: 0, mode: .screen, opacity: 1) == backdrop)
}

@Test func fuzzedExtremePixelsThrowOrStayFinite() throws {
    var rng = SplitMix64(seed: 18103)
    let values: [Float] = [0, -0.0, 1, -1, .leastNonzeroMagnitude, -.leastNonzeroMagnitude,
                           .greatestFiniteMagnitude, -.greatestFiniteMagnitude, 1e20, -1e20, 1e-30]
    func extreme(_ rng: inout SplitMix64) -> RGBA {
        RGBA(r: values[Int.random(in: 0..<values.count, using: &rng)],
             g: values[Int.random(in: 0..<values.count, using: &rng)],
             b: values[Int.random(in: 0..<values.count, using: &rng)],
             a: values[Int.random(in: 0..<values.count, using: &rng)])
    }
    for _ in 0..<200 {
        var source = try PixelBuffer(width: .random(in: 1...3, using: &rng), height: .random(in: 1...3, using: &rng))
        var backdrop = try PixelBuffer(width: .random(in: 1...3, using: &rng), height: .random(in: 1...3, using: &rng))
        for y in 0..<source.height { for x in 0..<source.width { try source.setPixel(x: x, y: y, extreme(&rng)) } }
        for y in 0..<backdrop.height { for x in 0..<backdrop.width { try backdrop.setPixel(x: x, y: y, extreme(&rng)) } }
        let x = Int.random(in: -3...3, using: &rng)
        let y = Int.random(in: -3...3, using: &rng)
        let mode = BlendMode.allCases[Int.random(in: 0..<BlendMode.allCases.count, using: &rng)]
        do {
            let out = try composite(source, onto: backdrop, x: x, y: y, mode: mode, opacity: .random(in: 0...1, using: &rng))
            for py in 0..<out.height { for px in 0..<out.width { #expect(try out.pixel(x: px, y: py).isFinite) } }
        } catch is RasterError {
            // A typed error is the contract for non-finite results.
        }
    }
}
