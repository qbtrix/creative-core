// CompositeTests.swift: composite(_:onto:mode:opacity:) against values worked
// out from the W3C Compositing and Blending Level 1 formulas, plus the exact
// cases (opacity 0, transparent source, opaque normal) and the throwing ones.
import CoreRaster
import Testing

/// A 1x1 buffer holding one straight-alpha color, stored premultiplied.
private func pixel(_ r: Float, _ g: Float, _ b: Float, _ a: Float) throws -> PixelBuffer {
    try PixelBuffer(width: 1, height: 1, fill: RGBA(r: r, g: g, b: b, a: a).premultiplied())
}

private func expectComposite(_ source: PixelBuffer, _ backdrop: PixelBuffer, opacity: Float,
                             _ table: [(BlendMode, [Float])]) throws {
    for (mode, want) in table {
        let got = try composite(source, onto: backdrop, mode: mode, opacity: opacity).pixel(x: 0, y: 0)
        let diffs = zip([got.r, got.g, got.b, got.a], want).map { abs($0 - $1) }
        #expect(diffs.allSatisfy { $0 <= 1e-6 }, "\(mode): got \(got), want \(want)")
    }
}

@Test func everyModeMatchesTheSpecOnOpaquePixels() throws {
    // Both opaque, so the result is B(Cb, Cs) itself. Cs = (0.8, 0.3, 0.5), Cb = (0.4, 0.6, 0.2).
    let table: [(BlendMode, [Float])] = [
        (.normal, [0.8, 0.3, 0.5, 1]),
        (.multiply, [0.32, 0.18, 0.1, 1]),
        (.screen, [0.88, 0.72, 0.6, 1]),
        (.overlay, [0.64, 0.44, 0.2, 1]),
        (.darken, [0.4, 0.3, 0.2, 1]),
        (.lighten, [0.8, 0.6, 0.5, 1]),
        (.colorDodge, [1, 0.857142857, 0.4, 1]),
        (.colorBurn, [0.25, 0, 0, 1]),
        (.hardLight, [0.76, 0.36, 0.2, 1]),
        (.softLight, [0.539473319, 0.504, 0.2, 1]),
        (.difference, [0.4, 0.3, 0.3, 1]),
        (.exclusion, [0.56, 0.54, 0.5, 1]),
        (.hue, [0.7584, 0.3584, 0.5184, 1]),
        (.saturation, [0.376, 0.626, 0.126, 1]),
        (.color, [0.824, 0.324, 0.524, 1]),
        (.luminosity, [0.376, 0.576, 0.176, 1]),
    ]
    #expect(table.map(\.0) == BlendMode.allCases)
    try expectComposite(pixel(0.8, 0.3, 0.5, 1), pixel(0.4, 0.6, 0.2, 1), opacity: 1, table)
}

@Test func everyModeMatchesTheSpecWithAlphaAndOpacity() throws {
    // Cs = (0.9, 0.2, 0.6) at alpha 0.6 and opacity 0.5 (so αs = 0.3), Cb = (0.1, 0.7, 0.95)
    // at alpha 0.5. Results are premultiplied; αo = 0.3 + 0.5 * 0.7 = 0.65.
    let table: [(BlendMode, [Float])] = [
        (.normal, [0.305, 0.305, 0.5125, 0.65]),
        (.multiply, [0.1835, 0.296, 0.508, 0.65]),
        (.screen, [0.3065, 0.389, 0.5695, 0.65]),
        (.overlay, [0.197, 0.353, 0.5665, 0.65]),
        (.darken, [0.185, 0.305, 0.5125, 0.65]),
        (.lighten, [0.305, 0.38, 0.565, 0.65]),
        (.colorDodge, [0.32, 0.40625, 0.5725, 0.65]),
        (.colorBurn, [0.17, 0.275, 0.56, 0.65]),
        (.hardLight, [0.293, 0.317, 0.5665, 0.65]),
        (.softLight, [0.20852, 0.3611, 0.565740383, 0.65]),
        (.difference, [0.29, 0.35, 0.475, 0.65]),
        (.exclusion, [0.293, 0.368, 0.484, 0.65]),
        (.hue, [0.32, 0.318469731, 0.52684417, 0.65]),
        (.saturation, [0.196845588, 0.375963235, 0.554345588, 0.65]),
        (.color, [0.319025, 0.319025, 0.526525, 0.65]),
        (.luminosity, [0.170975, 0.365975, 0.550975, 0.65]),
    ]
    #expect(table.map(\.0) == BlendMode.allCases)
    try expectComposite(pixel(0.9, 0.2, 0.6, 0.6), pixel(0.1, 0.7, 0.95, 0.5), opacity: 0.5, table)
}

@Test func nonSeparableModesClipToTheGamut() throws {
    // SetLum pushes red over 1 here (ClipColor's x > 1 branch)...
    try expectComposite(pixel(1, 0, 0, 1), pixel(0.9, 0.9, 0.9, 1), opacity: 1, [
        (.hue, [0.9, 0.9, 0.9, 1]), (.saturation, [0.9, 0.9, 0.9, 1]),
        (.color, [1, 0.857142857, 0.857142857, 1]), (.luminosity, [0.3, 0.3, 0.3, 1]),
    ])
    // ...and red under 0 here (the n < 0 branch).
    try expectComposite(pixel(0, 1, 1, 1), pixel(0.05, 0.05, 0.05, 1), opacity: 1, [
        (.hue, [0.05, 0.05, 0.05, 1]), (.saturation, [0.05, 0.05, 0.05, 1]),
        (.color, [0, 0.071428571, 0.071428571, 1]), (.luminosity, [0.7, 0.7, 0.7, 1]),
    ])
}

private func randomBuffer(_ w: Int, _ h: Int, _ rng: inout SplitMix64, alpha: ClosedRange<Float>) throws -> PixelBuffer {
    var buffer = try PixelBuffer(width: w, height: h)
    for y in 0..<h {
        for x in 0..<w {
            let p = RGBA(r: .random(in: 0...1, using: &rng), g: .random(in: 0...1, using: &rng),
                         b: .random(in: 0...1, using: &rng), a: .random(in: alpha, using: &rng))
            try buffer.setPixel(x: x, y: y, p.premultiplied())
        }
    }
    return buffer
}

@Test func exactCasesHoldForEveryModeOnRandomPixels() throws {
    var rng = SplitMix64(seed: 113)
    for _ in 0..<20 {
        let w = Int.random(in: 1...6, using: &rng)
        let h = Int.random(in: 1...6, using: &rng)
        let backdrop = try randomBuffer(w, h, &rng, alpha: 0...1)
        let source = try randomBuffer(w, h, &rng, alpha: 0...1)
        let transparent = try randomBuffer(w, h, &rng, alpha: 0...0)
        let opaque = try randomBuffer(w, h, &rng, alpha: 1...1)
        for mode in BlendMode.allCases {
            #expect(try composite(source, onto: backdrop, mode: mode, opacity: 0) == backdrop)
            #expect(try composite(transparent, onto: backdrop, mode: mode, opacity: 0.7) == backdrop)
        }
        #expect(try composite(opaque, onto: backdrop, mode: .normal, opacity: 1) == opaque)
    }
}

@Test func badSizesAndOpacitiesThrow() throws {
    let a = try PixelBuffer(width: 2, height: 3)
    for (w, h) in [(3, 2), (2, 2), (1, 3)] {
        let b = try PixelBuffer(width: w, height: h)
        #expect(throws: RasterError.self) { try composite(a, onto: b, mode: .normal, opacity: 1) }
        #expect(throws: RasterError.self) { try composite(b, onto: a, mode: .multiply, opacity: 1) }
    }
    for opacity: Float in [-0.001, 1.001, .nan, .infinity, -.infinity] {
        #expect(throws: RasterError.self) { try composite(a, onto: a, mode: .screen, opacity: opacity) }
    }
}

@Test func outOfRangePixelsGiveFiniteResultsOrThrowInEveryMode() throws {
    var rng = SplitMix64(seed: 1130)
    let edges: [Float] = [0, -0.0, 1, -1, 1e-30, -1e-30, 1e30, -1e30, .greatestFiniteMagnitude, .leastNonzeroMagnitude]
    func value() -> Float { Bool.random(using: &rng) ? edges.randomElement(using: &rng) ?? 0 : .random(in: -4...4, using: &rng) }
    var thrown = 0
    for _ in 0..<300 {
        var source = try PixelBuffer(width: 1, height: 1)
        var backdrop = try PixelBuffer(width: 1, height: 1)
        try source.setPixel(x: 0, y: 0, RGBA(r: value(), g: value(), b: value(), a: value()))
        try backdrop.setPixel(x: 0, y: 0, RGBA(r: value(), g: value(), b: value(), a: value()))
        for mode in BlendMode.allCases {
            do {
                // setPixel only stores finite values, so a returned buffer is finite.
                _ = try composite(source, onto: backdrop, mode: mode, opacity: .random(in: 0...1, using: &rng))
            } catch is RasterError {
                thrown += 1
            }
        }
    }
    #expect(thrown > 0)
}
