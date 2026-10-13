// FillRadialExtentAdversarialTests.swift: edge cases for the radial gradient
// edge check (#200). The limit is exact on both sides, moving a valid gradient
// past it is rejected, and a seeded fuzz over extreme values shows that every
// radial fill that validates also saves and exports to SVG and Lottie.
@testable import FlareCore
import Testing

@Suite struct FillRadialExtentAdversarialTests {
    static let stops = [GradientStop(offset: 0, color: .black), GradientStop(offset: 1, color: .white)]
    static let max = Double.greatestFiniteMagnitude

    static func doc(_ fill: Fill) -> Document {
        let shape = Shape(points: [Point(x: 0, y: 0), Point(x: 1, y: 1)], fill: fill)
        return Document(scenes: [Scene(id: "s", name: "S", layers: [Layer(id: "l", name: "L", shapes: [shape])])])
    }

    static func radial(_ x: Double, _ y: Double, _ r: Double) -> Fill {
        .radial(stops: stops, center: Point(x: x, y: y), radius: r)
    }

    /// Both edges land exactly on ±max: still finite, so accepted and exported.
    @Test(arguments: [(max / 2, max / 2), (-max / 2, max / 2), (max.nextDown, max.ulp), (0, max)] as [(Double, Double)])
    func edgeExactlyAtTheLimitIsAccepted(x: Double, r: Double) throws {
        let d = Self.doc(Self.radial(x, 0, r))
        try FlareFormat.validate(d)
        #expect(try !LottieExporter.export(scene: d.scenes[0]).isEmpty)
    }

    /// One step past the limit on either side is rejected with the edge message.
    @Test(arguments: [(max / 2, (max / 2).nextUp), (-max / 2, (max / 2).nextUp), (max.nextDown, max)])
    func edgeOneStepPastTheLimitIsRejected(x: Double, r: Double) {
        for fill in [Self.radial(x, 0, r), Self.radial(-x, 0, r)] {
            #expect(throws: ModelError.invalidFill("radial gradient center ± radius must be finite")) {
                try fill.validate()
            }
        }
    }

    /// The vertical axis is not part of the edge: a huge center.y is fine.
    @Test func hugeCenterYWithSmallRadiusIsAccepted() throws {
        let d = Self.doc(Self.radial(0, Self.max, 1))
        try FlareFormat.validate(d)
        _ = try LottieExporter.export(scene: d.scenes[0])
    }

    /// The radius check still runs first, so a bad radius keeps its own message.
    @Test(arguments: [0, -0.0, -1, Double.nan, .infinity, -.infinity])
    func badRadiusKeepsTheRadiusMessage(r: Double) {
        #expect(throws: ModelError.invalidFill("radial gradient radius must be finite and > 0")) {
            try Self.radial(Self.max, 0, r).validate()
        }
    }

    /// A gradient sitting on the limit cannot be dragged past it: the move
    /// throws and leaves the document and the undo stack as they were.
    @Test(arguments: [(max / 2, 1e300), (-max / 2, -1e300)])
    func movingAValidGradientPastTheLimitIsRejected(x: Double, dx: Double) throws {
        let start = Self.doc(Self.radial(x, 0, Self.max / 2))
        var e = CommandEngine(document: start)
        #expect(throws: CommandError.self) {
            try e.perform(TranslateShape(owner: .scene("s"), layerID: "l", index: 0, dx: dx, dy: 0))
        }
        #expect(e.document == start)
        #expect(!e.canUndo)
    }

    /// Seeded fuzz over extreme values: a radial fill either fails validation
    /// or round-trips through the format and exports to SVG and Lottie.
    @Test func everyValidatedRadialFillExports() throws {
        let pool: [Double] = [0, -0.0, 1, -1, 3, 1e-300, .leastNonzeroMagnitude, .leastNormalMagnitude,
                              Self.max, -Self.max, Self.max / 2, -Self.max / 2, (Self.max / 2).nextUp,
                              Self.max.nextDown, 1e308, -1e308, .nan, .infinity, -.infinity]
        var rng = SplitMix64(seed: 200)
        var accepted = 0
        for _ in 0..<2000 {
            let pick = { (rng: inout SplitMix64) in pool.randomElement(using: &rng) ?? 0 }
            let d = Self.doc(Self.radial(pick(&rng), pick(&rng), pick(&rng)))
            guard (try? FlareFormat.validate(d)) != nil else { continue }
            accepted += 1
            #expect(try FlareFormat.decode(FlareFormat.encode(d)) == d)
            _ = try SVGExporter.export(scene: d.scenes[0], frame: 0)
            _ = try LottieExporter.export(scene: d.scenes[0])
        }
        #expect(accepted > 200)
    }
}
