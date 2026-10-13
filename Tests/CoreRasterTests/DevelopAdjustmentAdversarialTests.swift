// DevelopAdjustmentAdversarialTests.swift: the develop sliders (white balance,
// contrast, highlights and shadows) beyond the acceptance test. Every slider
// at its range ends and at the smallest nonzero values, -0 as identity, a
// fine luminance ramp kept monotonic for every setting, contrast monotonic in
// its amount, grey luminance kept across the whole white balance grid,
// transparent and nearly transparent pixels, the largest finite pixel values
// throwing a RasterError instead of crashing, and a seeded fuzz of buffers
// and slider values that must either succeed with alpha intact or throw.
import CoreRaster
import Testing

private func grayRow(_ values: [Float]) throws -> PixelBuffer {
    var buffer = try PixelBuffer(width: values.count, height: 1)
    for (x, v) in values.enumerated() {
        try buffer.setPixel(x: x, y: 0, RGBA(r: v, g: v, b: v, a: 1))
    }
    return buffer
}

private func grays(_ buffer: PixelBuffer) throws -> [Float] {
    try (0..<buffer.width).map { try buffer.pixel(x: $0, y: 0).r }
}

private func luminance(_ p: RGBA) -> Float {
    let w = Histogram.luminanceWeights
    return w.r * p.r + w.g * p.g + w.b * p.b
}

/// A ramp 0...1 in 1/1000 steps, as one opaque grey row.
private func fineRamp() throws -> PixelBuffer {
    try grayRow((0...1000).map { Float($0) / 1000 })
}

private func isNondecreasing(_ values: [Float]) -> Bool {
    zip(values, values.dropFirst()).allSatisfy { $0 <= $1 }
}

private let sliderGrid = stride(from: Float(-100), through: 100, by: 25).map { $0 }

@Test func developNegativeZeroIsIdentity() throws {
    let buffer = try grayRow([0, 0.18, 0.5, 1, 1.5])
    #expect(try buffer.whiteBalance(temperature: -0.0, tint: -0.0) == buffer)
    #expect(try buffer.contrast(-0.0) == buffer)
    #expect(try buffer.highlightsShadows(highlights: -0.0, shadows: -0.0) == buffer)
}

@Test func developRangeEndsAreAcceptedAndJustBeyondThrow() throws {
    let buffer = try grayRow([0.02, 0.18, 0.9])
    for end in [Float(-100), 100] {
        _ = try buffer.whiteBalance(temperature: end, tint: end)
        _ = try buffer.contrast(end)
        _ = try buffer.highlightsShadows(highlights: end, shadows: end)
    }
    for bad in [Float(100).nextUp, Float(-100).nextDown, .greatestFiniteMagnitude,
                -.greatestFiniteMagnitude, .signalingNaN] {
        #expect(throws: RasterError.self) { try buffer.whiteBalance(temperature: bad, tint: 0) }
        #expect(throws: RasterError.self) { try buffer.contrast(bad) }
        #expect(throws: RasterError.self) { try buffer.highlightsShadows(highlights: 0, shadows: bad) }
    }
}

@Test func developTinyNonzeroValuesBarelyMovePixels() throws {
    let values: [Float] = [0, 0.02, 0.18, 0.5, 0.9, 1]
    let buffer = try grayRow(values)
    let tiny = Float.leastNonzeroMagnitude
    let results = [
        try buffer.whiteBalance(temperature: tiny, tint: -tiny),
        try buffer.contrast(tiny),
        try buffer.highlightsShadows(highlights: tiny, shadows: -tiny),
    ]
    for result in results {
        for (got, want) in zip(try grays(result), values) {
            #expect(abs(got - want) <= 1e-5)
        }
    }
}

@Test func whiteBalanceKeepsGreyLuminanceOverTheWholeGrid() throws {
    let grey = try grayRow([0.001, 0.18, 0.4, 1, 4])
    for temperature in sliderGrid {
        for tint in sliderGrid {
            let out = try grey.whiteBalance(temperature: temperature, tint: tint)
            for x in 0..<grey.width {
                let want = try grey.pixel(x: x, y: 0).r
                let got = luminance(try out.pixel(x: x, y: 0))
                #expect(abs(got - want) <= 1e-4 * max(1, want), "t \(temperature) tint \(tint) v \(want)")
            }
        }
    }
}

@Test func whiteBalanceDirectionHoldsAtEveryNonzeroSetting() throws {
    let grey = try grayRow([0.4])
    for amount in sliderGrid where amount != 0 {
        let warm = try grey.whiteBalance(temperature: amount, tint: 0).pixel(x: 0, y: 0)
        #expect(amount > 0 ? warm.r > warm.b : warm.r < warm.b, "temperature \(amount)")
        let tinted = try grey.whiteBalance(temperature: 0, tint: amount).pixel(x: 0, y: 0)
        #expect(amount > 0 ? tinted.g < tinted.r : tinted.g > tinted.r, "tint \(amount)")
    }
}

@Test func contrastIsMonotonicOnAFineRampAtEveryStep() throws {
    let ramp = try fineRamp()
    for amount in stride(from: Float(-100), through: 100, by: 5) {
        #expect(isNondecreasing(try grays(ramp.contrast(amount))), "contrast \(amount)")
    }
}

@Test func contrastMovesEachValueMonotonicallyWithTheAmount() throws {
    let values = (1...99).map { Float($0) / 100 }
    let ramp = try grayRow(values)
    var previous = try grays(ramp.contrast(-100))
    for amount in stride(from: Float(-95), through: 100, by: 5) {
        let current = try grays(ramp.contrast(amount))
        for (i, v) in values.enumerated() where abs(v - 0.18) > 1e-6 {
            // Above mid grey more contrast raises a value; below it lowers it.
            let ok = v > 0.18 ? current[i] >= previous[i] : current[i] <= previous[i]
            #expect(ok, "value \(v) from contrast \(amount - 5) to \(amount)")
        }
        previous = current
    }
}

@Test func contrastPushesEveryInRangeValueAwayFromMidGrey() throws {
    let values = (1...99).map { Float($0) / 100 }.filter { abs($0 - 0.18) > 1e-6 }
    let ramp = try grayRow(values)
    for amount in [Float(-100), -50, 50, 100] {
        let got = try grays(ramp.contrast(amount))
        for (v, out) in zip(values, got) {
            let before = abs(v - 0.18), after = abs(out - 0.18)
            #expect(amount > 0 ? after >= before : after <= before, "contrast \(amount) at \(v)")
        }
    }
}

@Test func highlightsShadowsKeepTheLuminanceRampMonotonic() throws {
    let ramp = try fineRamp()
    for highlights in sliderGrid {
        for shadows in sliderGrid {
            let mapped = try grays(ramp.highlightsShadows(highlights: highlights, shadows: shadows))
            #expect(isNondecreasing(mapped), "highlights \(highlights) shadows \(shadows)")
        }
    }
}

@Test func highlightsNeverTouchesShadowsAndShadowsNeverTouchesHighlights() throws {
    let dark: [Float] = [0, 0.001, 0.05, 0.1, 0.18]
    let bright: [Float] = [0.5, 0.75, 1, 2]
    for amount in sliderGrid {
        #expect(try grays(grayRow(dark).highlightsShadows(highlights: amount, shadows: 0)) == dark)
        #expect(try grays(grayRow(bright).highlightsShadows(highlights: 0, shadows: amount)) == bright)
    }
}

@Test func developSlidersOnTransparentPixelsStayTransparent() throws {
    let clear = try PixelBuffer(width: 3, height: 2)
    #expect(try clear.whiteBalance(temperature: 100, tint: -100) == clear)
    #expect(try clear.contrast(100) == clear)
    #expect(try clear.contrast(-100) == clear)
    #expect(try clear.highlightsShadows(highlights: 100, shadows: 100) == clear)
}

@Test func developSlidersKeepColorOfHalfTransparentPixels() throws {
    // A straight 0.5 grey at alpha 0.25 must come out as the same straight
    // value an opaque 0.5 does, times the same alpha.
    var half = try PixelBuffer(width: 1, height: 1)
    try half.setPixel(x: 0, y: 0, RGBA(r: 0.5, g: 0.5, b: 0.5, a: 0.25).premultiplied())
    let opaque = try grayRow([0.5])
    let pairs = [
        (try half.contrast(60), try opaque.contrast(60)),
        (try half.whiteBalance(temperature: 40, tint: 20), try opaque.whiteBalance(temperature: 40, tint: 20)),
        (try half.highlightsShadows(highlights: -70, shadows: 40),
         try opaque.highlightsShadows(highlights: -70, shadows: 40)),
    ]
    for (h, o) in pairs {
        let hp = try h.pixel(x: 0, y: 0).unpremultiplied(), op = try o.pixel(x: 0, y: 0)
        #expect(hp.a == 0.25)
        #expect(abs(hp.r - op.r) <= 1e-5 && abs(hp.g - op.g) <= 1e-5 && abs(hp.b - op.b) <= 1e-5)
    }
}

@Test func developSlidersThrowOnOverflowInsteadOfCrashing() throws {
    let huge = try PixelBuffer(width: 1, height: 1,
                               fill: RGBA(r: .greatestFiniteMagnitude, g: .greatestFiniteMagnitude,
                                          b: .greatestFiniteMagnitude, a: 1))
    #expect(throws: RasterError.self) { try huge.whiteBalance(temperature: 100, tint: 0) }
    #expect(throws: RasterError.self) { try huge.highlightsShadows(highlights: 100, shadows: 0) }
}

@Test func developSlidersFuzzSucceedWithAlphaIntactOrThrow() throws {
    var rng = SplitMix64(seed: 0x231_246)
    for _ in 0..<200 {
        let w = Int.random(in: 1...5, using: &rng), h = Int.random(in: 1...5, using: &rng)
        var buffer = try PixelBuffer(width: w, height: h)
        for y in 0..<h {
            for x in 0..<w {
                try buffer.setPixel(x: x, y: y, randomPixel(&rng).premultiplied())
            }
        }
        func slider() -> Float {
            switch Int.random(in: 0..<6, using: &rng) {
            case 0: return .nan
            case 1: return Float.random(in: 100.001...1e6, using: &rng)
            case 2: return -Float.random(in: 100.001...1e6, using: &rng)
            default: return Float.random(in: -100...100, using: &rng)
            }
        }
        let a = slider(), b = slider()
        let valid = [a, b].allSatisfy { $0.isFinite && abs($0) <= 100 }
        let calls: [() throws -> PixelBuffer] = [
            { try buffer.whiteBalance(temperature: a, tint: b) },
            { try buffer.contrast(a) },
            { try buffer.highlightsShadows(highlights: a, shadows: b) },
        ]
        for (k, call) in calls.enumerated() {
            let needsB = k != 1
            let ok = needsB ? valid : (a.isFinite && abs(a) <= 100)
            do {
                let out = try call()
                #expect(ok, "call \(k) accepted \(a), \(b)")
                for y in 0..<h {
                    for x in 0..<w {
                        #expect(try out.pixel(x: x, y: y).a == buffer.pixel(x: x, y: y).a)
                    }
                }
            } catch is RasterError {
                #expect(!ok, "call \(k) threw on valid \(a), \(b)")
            }
        }
    }
}
