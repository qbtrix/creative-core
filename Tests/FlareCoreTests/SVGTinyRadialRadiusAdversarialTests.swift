// SVGTinyRadialRadiusAdversarialTests.swift: edge cases for the SVG radial
// radius that rounds below the 4-decimal step (#234, #238). Both sides of the
// rounding step, the smallest Doubles, and a seeded fuzz over tiny radii show
// that every radial fill that validates exports a positive, exponent-free r
// that parses back to the radius.
@testable import FlareCore
import Testing

@Suite struct SVGTinyRadialRadiusAdversarialTests {
    static func doc(_ x: Double, _ y: Double, _ r: Double) -> Document {
        FillRadialExtentAdversarialTests.doc(FillRadialExtentAdversarialTests.radial(x, y, r))
    }

    /// The text of the first radial gradient's r attribute.
    static func radiusText(_ svg: String) -> String? {
        guard let tag = svg.split(separator: "\n").first(where: { $0.hasPrefix("<radialGradient") }),
              let start = tag.range(of: " r=\"") else { return nil }
        let rest = tag[start.upperBound...]
        return rest.firstIndex(of: "\"").map { String(rest[..<$0]) }
    }

    static func exportedRadius(_ x: Double, _ y: Double, _ r: Double) throws -> String? {
        let d = doc(x, y, r)
        try FlareFormat.validate(d)
        return radiusText(try SVGExporter.export(scene: d.scenes[0], frame: 0))
    }

    static func isPlainPositive(_ text: String) -> Bool {
        !text.contains(where: { $0 == "e" || $0 == "E" || $0 == "-" }) && (Double(text) ?? 0) > 0
    }

    /// Either side of the 0.00005 rounding step stays positive and plain.
    @Test(arguments: [(0.00005 as Double).nextDown, 0.00005, (0.00005 as Double).nextUp, 0.000049999, 0.0000500001, 0.00004, 0.00001])
    func radiusAroundTheRoundingStepStaysPositive(r: Double) throws {
        let text = try #require(try Self.exportedRadius(5, 5, r))
        #expect(Self.isPlainPositive(text), "r=\(r) exported as \(text)")
    }

    /// The smallest Doubles are written in full and parse back exactly.
    @Test(arguments: [Double.leastNonzeroMagnitude, .leastNormalMagnitude, 1e-300, 1e-100, 1e-10, 4.9999e-5])
    func smallestRadiiRoundTripExactly(r: Double) throws {
        let text = try #require(try Self.exportedRadius(0, 0, r))
        #expect(Self.isPlainPositive(text), "r=\(r) exported as \(text)")
        #expect(Double(text) == r)
    }

    /// Radii at or above the step still use the rounded form.
    @Test(arguments: [(0.00006, "0.0001"), (0.0001, "0.0001"), (1, "1"), (12.34567, "12.3457"), (1e20, "100000000000000000000")])
    func radiiAboveTheStepAreRounded(r: Double, expected: String) throws {
        #expect(try Self.exportedRadius(0, 0, r) == expected)
    }

    /// The center is still rounded as before, only r changes.
    @Test func centerStaysRoundedNextToATinyRadius() throws {
        let d = Self.doc(1.234567, -7.654321, 0.00001)
        try FlareFormat.validate(d)
        let svg = try SVGExporter.export(scene: d.scenes[0], frame: 0)
        #expect(svg.contains("cx=\"1.2346\" cy=\"-7.6543\" r=\"0.00001\""))
    }

    /// A non-finite radius that skipped validation still throws, never writes.
    @Test(arguments: [Double.nan, .infinity, -.infinity])
    func nonFiniteRadiusThrows(r: Double) {
        let d = Self.doc(0, 0, r)
        #expect(throws: SVGExportError.nonFiniteValue) {
            _ = try SVGExporter.export(scene: d.scenes[0], frame: 0)
        }
    }

    /// Seeded fuzz: every valid radial fill with a tiny radius exports a plain
    /// positive r; below the step it is exact, above it within half a step.
    @Test func fuzzTinyValidRadiiExportPositive() throws {
        var rng = SplitMix64(seed: 234)
        let centers: [Double] = [0, 1e-300, -1e-10, 0.00003, 5, -1000, 1e6]
        var exported = 0
        for _ in 0..<3000 {
            // 2^-1074 (the smallest subnormal) up to about 6e-5, across the step.
            let r = Double(sign: .plus, exponent: Int.random(in: -1074 ... -15, using: &rng),
                           significand: Double.random(in: 1..<2, using: &rng))
            let x = centers[Int(rng.next() % UInt64(centers.count))]
            let d = Self.doc(x, x, r)
            guard (try? FlareFormat.validate(d)) != nil else { continue }
            let text = try #require(Self.radiusText(try SVGExporter.export(scene: d.scenes[0], frame: 0)))
            #expect(Self.isPlainPositive(text), "r=\(r) at \(x) exported as \(text)")
            let parsed = Double(text) ?? -1
            if r < 0.00005 && text != "0.0001" {
                #expect(parsed == r, "r=\(r) exported as \(text)")
            } else {
                #expect(abs(parsed - r) <= 0.00005, "r=\(r) exported as \(text)")
            }
            exported += 1
        }
        #expect(exported > 500)
    }
}
