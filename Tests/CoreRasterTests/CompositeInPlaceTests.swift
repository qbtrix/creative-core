// CompositeInPlaceTests.swift: PixelBuffer.composite(_:x:y:mode:opacity:),
// the in-place composite, against a frozen copy of the per-pixel loop and
// sourceOver it replaced. Every blend mode at opacities 0, 0.37 and 1 with the
// source hanging off each edge and corner or wholly outside; the free
// functions; bad opacities; an overflow to infinity (same message, nothing
// non-finite stored); the opaque .normal row copy, only at opacity 1 (an opaque
// source at 0.37 and 0 takes the formula), including a row with one pixel that
// is not quite opaque; and a Flatten, two chained composites over
// three layers.
@testable import CoreRaster
import Testing

/// The composite loop as it was before the in-place method: a copy of the
/// backdrop written pixel by pixel through setPixel.
private func referenceComposite(_ source: PixelBuffer, onto backdrop: PixelBuffer, x: Int, y: Int,
                                mode: BlendMode, opacity: Float) throws -> PixelBuffer {
    guard (0...1).contains(opacity) else {
        throw RasterError.invalid("opacity \(opacity): must be a finite value in 0...1")
    }
    guard x < backdrop.width, y < backdrop.height, x > -source.width, y > -source.height else {
        return backdrop
    }
    var result = backdrop
    for by in max(y, 0)..<min(y + source.height, backdrop.height) {
        for bx in max(x, 0)..<min(x + source.width, backdrop.width) {
            let s = try source.pixel(x: bx - x, y: by - y)
            let b = try backdrop.pixel(x: bx, y: by)
            try result.setPixel(x: bx, y: by, referenceSourceOver(s, b, mode: mode, opacity: opacity))
        }
    }
    return result
}

private func referenceSourceOver(_ source: RGBA, _ b: RGBA, mode: BlendMode, opacity: Float) -> RGBA {
    let s = RGBA(r: source.r * opacity, g: source.g * opacity, b: source.b * opacity, a: source.a * opacity)
    let cs = s.unpremultiplied()
    let blended = mode.blend(backdrop: b.unpremultiplied(), source: cs)
    let mixed = RGBA(r: cs.r + b.a * (blended.r - cs.r), g: cs.g + b.a * (blended.g - cs.g),
                     b: cs.b + b.a * (blended.b - cs.b), a: s.a).premultiplied()
    let rest = 1 - s.a
    return RGBA(r: mixed.r + b.r * rest, g: mixed.g + b.g * rest, b: mixed.b + b.b * rest, a: s.a + b.a * rest)
}

private func randomBuffer(_ w: Int, _ h: Int, _ rng: inout SplitMix64, opaque: Bool = false) throws -> PixelBuffer {
    var buffer = try PixelBuffer(width: w, height: h)
    for y in 0..<h {
        for x in 0..<w {
            var p = randomPixel(&rng)
            if opaque { p.a = 1 }
            try buffer.setPixel(x: x, y: y, p.premultiplied())
        }
    }
    return buffer
}

/// The thrown RasterError message, or nil when `body` does not throw.
private func message(_ body: () throws -> Void) -> String? {
    do {
        try body()
        return nil
    } catch RasterError.invalid(let text) {
        return text
    } catch {
        return "unexpected \(error)"
    }
}

private func allFinite(_ buffer: PixelBuffer) -> Bool {
    buffer.components.allSatisfy { $0.isFinite }
}

/// Offsets for a 4x3 source on a 7x5 backdrop: each corner and edge hanging
/// off, inside, exactly on the far edges, and wholly outside on each side.
private let offsets = [(-2, -1), (5, -1), (-2, 3), (5, 3), (2, -2), (2, 4), (-3, 1), (5, 1),
                       (1, 1), (3, 2), (7, 0), (0, 5), (-4, 0), (0, -3), (-9, -9)]

@Test func everyModeAndOffsetMatchesTheReference() throws {
    var rng = SplitMix64(seed: 311)
    let backdrop = try randomBuffer(7, 5, &rng)
    let source = try randomBuffer(4, 3, &rng)
    let big = try randomBuffer(9, 8, &rng)
    for mode in BlendMode.allCases {
        for opacity: Float in [0, 0.37, 1] {
            for (x, y) in offsets + [(0, 0)] {
                let want = try referenceComposite(source, onto: backdrop, x: x, y: y, mode: mode, opacity: opacity)
                var got = backdrop
                try got.composite(source, x: x, y: y, mode: mode, opacity: opacity)
                #expect(got == want, "\(mode) \(opacity) at (\(x), \(y))")
                #expect(try composite(source, onto: backdrop, x: x, y: y, mode: mode, opacity: opacity) == want)
            }
            // A source larger than the backdrop on every side.
            var covered = backdrop
            try covered.composite(big, x: -1, y: -2, mode: mode, opacity: opacity)
            #expect(covered == (try referenceComposite(big, onto: backdrop, x: -1, y: -2, mode: mode,
                                                       opacity: opacity)), "\(mode) \(opacity) larger")
            // The same-size free function.
            let twin = try randomBuffer(7, 5, &rng)
            #expect(try composite(twin, onto: backdrop, mode: mode, opacity: opacity)
                    == (try referenceComposite(twin, onto: backdrop, x: 0, y: 0, mode: mode, opacity: opacity)))
        }
    }
}

@Test func badOpacityThrowsAndChangesNothing() throws {
    var rng = SplitMix64(seed: 312)
    let backdrop = try randomBuffer(5, 4, &rng)
    let source = try randomBuffer(3, 3, &rng)
    for opacity: Float in [.nan, -0.1, 1.1, .infinity] {
        var got = backdrop
        let thrown = message { try got.composite(source, x: 1, y: 1, mode: .multiply, opacity: opacity) }
        #expect(thrown == "opacity \(opacity): must be a finite value in 0...1")
        #expect(got == backdrop)
        #expect(message { _ = try composite(source, onto: backdrop, x: 1, y: 1, mode: .multiply,
                                            opacity: opacity) } == thrown)
    }
}

@Test func overflowThrowsTheSameMessageAndStoresNothingNonFinite() throws {
    var rng = SplitMix64(seed: 313)
    let backdrop = try randomBuffer(6, 5, &rng)
    var source = try randomBuffer(4, 3, &rng)
    // Premultiplied 1e30 over alpha 1e-45: unpremultiplying overflows Float.
    try source.setPixel(x: 2, y: 1, RGBA(r: 1e30, g: 0, b: 0, a: 1e-45))
    for mode in [BlendMode.normal, .multiply, .luminosity] {
        let want = message { _ = try referenceComposite(source, onto: backdrop, x: 1, y: 1, mode: mode, opacity: 1) }
        #expect(want?.hasSuffix("at (3, 2): components must be finite") == true, "\(mode): \(want ?? "no throw")")
        #expect(message { _ = try composite(source, onto: backdrop, x: 1, y: 1, mode: mode, opacity: 1) } == want)
        var got = backdrop
        #expect(message { try got.composite(source, x: 1, y: 1, mode: mode, opacity: 1) } == want)
        #expect(allFinite(got))
        // The failing row and every row after it are untouched.
        for y in 2..<5 {
            for x in 0..<6 {
                #expect(try got.pixel(x: x, y: y) == backdrop.pixel(x: x, y: y), "(\(x), \(y))")
            }
        }
    }
}

@Test func opaqueNormalRowsEqualTheReference() throws {
    var rng = SplitMix64(seed: 314)
    let backdrop = try randomBuffer(8, 6, &rng)
    var source = try randomBuffer(5, 4, &rng, opaque: true)
    // Below full opacity an opaque row is no longer the source: it takes the formula.
    for opacity: Float in [1, 0.37, 0] {
        for (x, y) in [(0, 0), (-2, -1), (5, 4), (2, 1)] {
            var got = backdrop
            try got.composite(source, x: x, y: y, mode: .normal, opacity: opacity)
            #expect(got == (try referenceComposite(source, onto: backdrop, x: x, y: y, mode: .normal,
                                                   opacity: opacity)), "\(opacity) at (\(x), \(y))")
        }
    }
    // One pixel just short of opaque: its row must take the formula, not the copy.
    try source.setPixel(x: 3, y: 2, RGBA(r: 0.5, g: -0.4, b: 0.9, a: 0.999).premultiplied())
    var got = backdrop
    try got.composite(source, x: 1, y: 1, mode: .normal, opacity: 1)
    #expect(got == (try referenceComposite(source, onto: backdrop, x: 1, y: 1, mode: .normal, opacity: 1)))
}

@Test func flattenOfThreeLayersEqualsTwoChainedReferenceComposites() throws {
    var rng = SplitMix64(seed: 315)
    let bottom = try randomBuffer(9, 7, &rng)
    let middle = try randomBuffer(9, 7, &rng)
    let top = try randomBuffer(5, 4, &rng)
    let opaqueTop = try randomBuffer(9, 7, &rng, opaque: true)
    let cases: [(BlendMode, Float, BlendMode, Float, PixelBuffer, Int, Int)] = [
        (.normal, 1, .normal, 1, top, 3, 2), (.normal, 1, .normal, 1, opaqueTop, 0, 0),
        (.multiply, 0.37, .normal, 1, top, -2, 4), (.normal, 0.37, .screen, 1, top, 6, -1),
        (.overlay, 1, .luminosity, 0.37, opaqueTop, 1, 1), (.colorBurn, 0, .hue, 1, top, 2, 2),
    ]
    for (lowerMode, lowerOpacity, upperMode, upperOpacity, layer, x, y) in cases {
        let once = try referenceComposite(middle, onto: bottom, x: 0, y: 0, mode: lowerMode, opacity: lowerOpacity)
        let want = try referenceComposite(layer, onto: once, x: x, y: y, mode: upperMode, opacity: upperOpacity)
        var got = bottom
        try got.composite(middle, x: 0, y: 0, mode: lowerMode, opacity: lowerOpacity)
        try got.composite(layer, x: x, y: y, mode: upperMode, opacity: upperOpacity)
        #expect(got == want, "\(lowerMode) \(lowerOpacity) then \(upperMode) \(upperOpacity) at (\(x), \(y))")
        #expect(got != bottom)
    }
}
