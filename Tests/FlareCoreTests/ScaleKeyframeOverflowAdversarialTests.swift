// ScaleKeyframeOverflowAdversarialTests.swift: adversarial routes around the
// scale × 100 validation check (#208, PR #241). Non-finite values keep their
// own error, the check names the right frame in a long track, extreme but
// safe values still validate, the engine refuses the value on every scale
// axis, and a seeded fuzz shows every scene-layer scale track that validates
// exports to Lottie.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Testing
@testable import FlareCore

@Suite struct ScaleKeyframeOverflowAdversarialTests {
    /// The largest scale whose × 100 is still finite.
    static let limit = ScaleKeyframeOverflowTests.firstOverflow.nextDown

    static func doc(_ property: String, _ track: [Keyframe]) -> Document {
        var d = Fixtures.document()
        d.scenes[0].layers[1].tracks[property] = track
        return d
    }

    /// NaN and the infinities fail the finite check first, with its message,
    /// not the overflow one.
    @Test(arguments: [Double.nan, .infinity, -.infinity])
    func nonFiniteKeepsItsOwnError(value: Double) {
        #expect(throws: FormatError.invalid("layer ball: track scaleY has a non-finite value at frame 0")) {
            try FlareFormat.validate(Self.doc("scaleY", [Keyframe(frame: 0, value: value)]))
        }
    }

    /// greatestFiniteMagnitude itself, either sign, is rejected as an overflow.
    @Test(arguments: [Double.greatestFiniteMagnitude, -.greatestFiniteMagnitude])
    func greatestFiniteMagnitudeIsRejected(value: Double) {
        #expect(throws: FormatError.invalid("layer ball: track scaleX value × 100 overflows at frame 0")) {
            try FlareFormat.validate(Self.doc("scaleX", [Keyframe(frame: 0, value: value)]))
        }
    }

    /// Only the offending keyframe of a long track is named, even when it is
    /// the last one and the earlier ones sit right at the limit.
    @Test func namesTheOverflowingFrame() {
        var track = (0..<50).map { Keyframe(frame: $0 * 2, value: $0.isMultiple(of: 2) ? Self.limit : -Self.limit) }
        track.append(Keyframe(frame: 1000, value: -Self.limit.nextUp.nextUp))
        #expect(throws: FormatError.invalid("layer ball: track scaleX value × 100 overflows at frame 1000")) {
            try FlareFormat.validate(Self.doc("scaleX", track))
        }
    }

    /// Zero, negative zero, subnormals and the limit itself validate and export.
    @Test(arguments: [0.0, -0.0, Double.leastNonzeroMagnitude, -Double.leastNormalMagnitude, limit, -limit])
    func extremeSafeValuesExport(value: Double) throws {
        let d = Self.doc("scaleY", [Keyframe(frame: 0, value: value)])
        try FlareFormat.validate(d)
        let data = try LottieExporter.export(scene: d.scenes[0])
        let lottie = try JSONDecoder().decode(ScaleKeyframeOverflowTests.Lottie.self, from: data)
        #expect(lottie.layers.contains { $0.ks.s.k == [100, value * 100] })
    }

    /// The engine refuses an overflowing scaleY added after a valid track,
    /// and the refused perform leaves the undo stack alone.
    @Test func engineRefusesScaleYAndKeepsHistory() throws {
        var e = CommandEngine(document: Fixtures.document())
        try e.perform(SetKeyframe(sceneID: "s1", layerID: "ball", property: "scaleY",
                                  keyframe: Keyframe(frame: 0, value: Self.limit)))
        let before = e.document
        #expect(throws: CommandError.self) {
            try e.perform(SetKeyframe(sceneID: "s1", layerID: "ball", property: "scaleY",
                                      keyframe: Keyframe(frame: 5, value: -1e307)))
        }
        #expect(e.document == before)
        try e.undo()
        #expect(e.document == Fixtures.document())
    }

    /// A linear symbol tween from -limit to +limit, sampled just before its
    /// end, stays within the limit and exports.
    @Test func symbolLinearTweenAtTheLimitExports() throws {
        var d = Fixtures.document()
        d.symbols = [Symbol(id: "sym", name: "Sym", durationFrames: 10, layers: [
            Layer(id: "wing", name: "Wing", tracks: ["scaleX": [
                Keyframe(frame: 0, value: -Self.limit), Keyframe(frame: 7, value: Self.limit),
            ]]),
        ])]
        for frame in 0..<10 {
            d.scenes[0].layers[1].instances = [Instance(symbolID: "sym", firstFrame: frame, loop: .singleFrame)]
            try FlareFormat.validate(d)
            _ = try LottieExporter.export(scene: d.scenes[0], symbols: d.symbols)
        }
    }

    /// Seeded fuzz over magnitudes from 1e-300 to past the limit: a scene
    /// layer scale track either fails validation or exports to Lottie.
    @Test(arguments: [UInt64(1), 208, 241])
    func fuzzValidatesIffExports(seed: UInt64) throws {
        var rng = SplitMix64(seed: seed)
        for _ in 0..<300 {
            let count = Int.random(in: 1...4, using: &rng)
            let track = (0..<count).map { i in
                let mantissa = Double.random(in: -10...10, using: &rng)
                let exponent = Int.random(in: -300...308, using: &rng)
                return Keyframe(frame: i * 3, value: mantissa * Self.pow10(exponent))
            }
            let property = Bool.random(using: &rng) ? "scaleX" : "scaleY"
            let d = Self.doc(property, track)
            let overflows = track.contains { !($0.value * 100).isFinite }
            if overflows {
                #expect(throws: FormatError.self) { try FlareFormat.validate(d) }
            } else {
                try FlareFormat.validate(d)
                _ = try LottieExporter.export(scene: d.scenes[0])
            }
        }
    }

    /// 10^e by repeated squaring, Foundation-free; overflows to infinity past 1e308.
    static func pow10(_ e: Int) -> Double {
        var result = 1.0
        var base = e < 0 ? 0.1 : 10.0
        var n = abs(e)
        while n > 0 {
            if n & 1 == 1 { result *= base }
            base *= base
            n >>= 1
        }
        return result
    }
}
