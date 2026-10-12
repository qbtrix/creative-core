// MaskTests.swift: Mask size validation, shape coverage (rectangle, ellipse,
// even-odd polygon), the combine operations, and a seeded polygon fuzz.
import CoreRaster
import Testing

private func within1Percent(_ area: Double, _ expected: Double) -> Bool {
    abs(area - expected) <= expected * 0.01
}

@Test func maskSizeRulesMatchPixelBuffer() throws {
    for (w, h) in [(0, 1), (1, 0), (-3, 4), (16_385, 16_384), (Int.max, 2)] {
        #expect(throws: RasterError.self) { try Mask(width: w, height: h) }
    }
    #expect(throws: RasterError.self) { try Mask(width: 2, height: 2, fill: 1.5) }
    #expect(throws: RasterError.self) { try Mask(width: 2, height: 2, fill: .nan) }
    let mask = try Mask(width: 3, height: 2, fill: 0.25)
    #expect(mask.width == 3 && mask.height == 2)
    #expect(try mask.coverage(x: 2, y: 1) == 0.25)
    #expect(mask.area == 1.5)
    #expect(throws: RasterError.self) { try mask.coverage(x: 3, y: 0) }
    #expect(throws: RasterError.self) { try mask.coverage(x: 0, y: -1) }
}

@Test func shapesCoverTheirAreaWithinOnePercent() throws {
    let rect = try Mask.rectangle(width: 200, height: 200, x: 20.3, y: 30.7, w: 100, h: 50)
    #expect(within1Percent(rect.area, 5000))
    #expect(try rect.coverage(x: 60, y: 50) == 1)
    #expect(try rect.coverage(x: 10, y: 10) == 0)
    let partial = try rect.coverage(x: 20, y: 50)
    #expect(partial > 0 && partial < 1)

    let circle = try Mask.ellipse(width: 200, height: 200, centerX: 100, centerY: 100, radiusX: 40, radiusY: 40)
    #expect(within1Percent(circle.area, Double.pi * 40 * 40))
    #expect(try circle.coverage(x: 100, y: 100) == 1)
    #expect(try circle.coverage(x: 145, y: 100) == 0)

    let triangle = try Mask.polygon(width: 200, height: 200, points: [
        Mask.Point(x: 10, y: 10), Mask.Point(x: 110, y: 10), Mask.Point(x: 10, y: 110),
    ])
    #expect(within1Percent(triangle.area, 5000))
    #expect(try triangle.coverage(x: 20, y: 20) == 1)
    #expect(try triangle.coverage(x: 100, y: 100) == 0)
}

@Test func polygonUsesEvenOddAndClipsToTheMask() throws {
    // Two overlapping squares as one polygon path: the overlap is outside.
    let square = { (x: Double, y: Double) in
        [Mask.Point(x: x, y: y), Mask.Point(x: x + 20, y: y), Mask.Point(x: x + 20, y: y + 20),
         Mask.Point(x: x, y: y + 20), Mask.Point(x: x, y: y)]
    }
    let mask = try Mask.polygon(width: 50, height: 50, points: square(0, 0) + square(10, 10))
    #expect(try mask.coverage(x: 5, y: 5) == 1)
    #expect(try mask.coverage(x: 15, y: 15) == 0)
    #expect(try mask.coverage(x: 25, y: 25) == 1)
    #expect(mask.area == 600)
    // A shape far bigger than the mask fills it; one entirely off it is empty.
    let huge = try Mask.rectangle(width: 4, height: 4, x: -1e300, y: -1e300, w: 1e308, h: 1e308)
    #expect(huge.area == 16)
    let off = try Mask.ellipse(width: 4, height: 4, centerX: -100, centerY: 2, radiusX: 3, radiusY: 3)
    #expect(off.area == 0)
    #expect(try Mask.polygon(width: 4, height: 4, points: [Mask.Point(x: 0, y: 0), Mask.Point(x: 4, y: 4)]).area == 0)
}

@Test func invalidShapeParametersThrow() {
    #expect(throws: RasterError.self) { try Mask.rectangle(width: 8, height: 8, x: .nan, y: 0, w: 1, h: 1) }
    #expect(throws: RasterError.self) { try Mask.rectangle(width: 8, height: 8, x: 0, y: 0, w: -1, h: 1) }
    #expect(throws: RasterError.self) { try Mask.ellipse(width: 8, height: 8, centerX: 0, centerY: .infinity, radiusX: 1, radiusY: 1) }
    #expect(throws: RasterError.self) { try Mask.ellipse(width: 8, height: 8, centerX: 0, centerY: 0, radiusX: -1, radiusY: 1) }
    #expect(throws: RasterError.self) {
        try Mask.polygon(width: 8, height: 8, points: [Mask.Point(x: 0, y: 0), Mask.Point(x: 1, y: .nan), Mask.Point(x: 2, y: 0)])
    }
    #expect(throws: RasterError.self) { try Mask.rectangle(width: 0, height: 8, x: 0, y: 0, w: 1, h: 1) }
}

@Test func combiningMasks() throws {
    let empty = try Mask(width: 200, height: 200)
    let circle = try Mask.ellipse(width: 200, height: 200, centerX: 90, centerY: 110, radiusX: 40, radiusY: 30)

    var added = circle
    try added.add(empty)
    #expect(added == circle)

    var intersected = circle
    try intersected.intersect(empty)
    #expect(intersected == empty)

    var twice = circle
    twice.invert()
    #expect(twice != circle)
    twice.invert()
    #expect(twice == circle)

    var all = try Mask(width: 200, height: 200, fill: 1)
    try all.subtract(circle)
    var inverted = circle
    inverted.invert()
    #expect(all == inverted)

    // Clamped to 0...1.
    var full = try Mask(width: 2, height: 2, fill: 0.75)
    try full.add(Mask(width: 2, height: 2, fill: 0.5))
    #expect(full.area == 4)
    var none = try Mask(width: 2, height: 2, fill: 0.25)
    try none.subtract(Mask(width: 2, height: 2, fill: 0.5))
    #expect(none.area == 0)

    var a = try Mask(width: 2, height: 3)
    let before = a
    #expect(throws: RasterError.self) { try a.add(Mask(width: 3, height: 2)) }
    #expect(throws: RasterError.self) { try a.subtract(Mask(width: 2, height: 2)) }
    #expect(throws: RasterError.self) { try a.intersect(Mask(width: 1, height: 3)) }
    #expect(a == before)
}

@Test func polygonFuzzNeverCrashesAndStaysInRange() throws {
    var rng = SplitMix64(seed: 115)
    let specials: [Double] = [.nan, .infinity, -.infinity, 1e308, -1e308, 1e-300, 0, .greatestFiniteMagnitude]
    var threw = 0
    for _ in 0..<300 {
        let count = Int.random(in: 0...8, using: &rng)
        let points = (0..<count).map { _ in
            let pick = { (rng: inout SplitMix64) -> Double in
                Int.random(in: 0..<5, using: &rng) == 0
                    ? specials.randomElement(using: &rng) ?? 0
                    : Double.random(in: -10...30, using: &rng)
            }
            return Mask.Point(x: pick(&rng), y: pick(&rng))
        }
        let finite = points.allSatisfy { $0.x.isFinite && $0.y.isFinite }
        do {
            let mask = try Mask.polygon(width: 16, height: 16, points: points)
            #expect(finite)
            #expect(mask.area >= 0 && mask.area <= 256)
            for y in 0..<16 {
                for x in 0..<16 { #expect((0...1).contains(try mask.coverage(x: x, y: y))) }
            }
        } catch {
            #expect(!finite)
            #expect(error is RasterError)
            threw += 1
        }
    }
    #expect(threw > 20)
}
