// UnsharpRuleTests.swift: the Metal unsharp kernel's rule (MB-12) gives CoreRaster's `unsharpMask` exactly, the
// threshold strict; invalid parameters and a non-finite result throw the CPU backend's exact errors.
import CoreRaster
import CoreRender
import Testing

@Suite struct UnsharpRuleTests {
    /// Each component of a one-pixel-high buffer through the rule, against CoreRaster's blur of the buffer,
    /// equals CoreRaster's unsharp mask of it with `==`.
    @Test func matchesCoreRasterOnALine() throws {
        var rng = ParityRandom(seed: 0x5A4B)
        for (amount, threshold) in [(1.0, 0.0), (0.0, 0.0), (2.5, 0.05), (-0.5, 0.02), (1.5, 0.2), (3, 1)] {
            for (length, sigma) in [(1, 0.0), (9, 1.0), (61, 2.5)] {
                var buffer = try PixelBuffer(width: length, height: 1)
                for x in 0..<length {
                    let a = Float.random(in: 0...1, using: &rng)
                    try buffer.setPixel(x: x, y: 0, RGBA(r: Float.random(in: 0...a, using: &rng), g: a / 3, b: 0, a: a))
                }
                let want = try buffer.unsharpMask(amount: amount, sigma: sigma, threshold: threshold)
                let blurred = try buffer.gaussianBlur(sigma: sigma)
                let rule = try UnsharpRule(amount: amount, threshold: threshold)
                for x in 0..<length {
                    let (p, b, w) = (try buffer.pixel(x: x, y: 0), try blurred.pixel(x: x, y: 0), try want.pixel(x: x, y: 0))
                    let got = RGBA(r: rule.apply(p.r, blurred: b.r), g: rule.apply(p.g, blurred: b.g),
                                   b: rule.apply(p.b, blurred: b.b), a: rule.apply(p.a, blurred: b.a))
                    #expect(got == w, "amount \(amount) threshold \(threshold) sigma \(sigma) pixel \(x)")
                }
            }
        }
    }

    /// A difference exactly at the threshold is left alone; one just over it is sharpened.
    @Test func theThresholdIsStrict() throws {
        let rule = try UnsharpRule(amount: 2, threshold: 0.25)
        #expect(rule.apply(0.75, blurred: 0.5) == 0.75, "at the threshold: unchanged")
        #expect(rule.apply(0.5, blurred: 0.75) == 0.5)
        #expect(rule.apply(0.875, blurred: 0.5) == 1.625, "over it: 0.875 + 2 x 0.375")
        #expect(rule.apply(0.5, blurred: 0.875) == -0.25)
        #expect(rule.parameters == [2, 0.25])
    }

    /// Every amount or threshold CoreRaster rejects throws the same `RenderError` from the rule as from the CPU
    /// backend; an amount that overflows a component throws the CPU's overflow error from `check`.
    @Test func invalidParametersThrowTheCPUBackendsError() throws {
        let cpu = CPUBackend()
        var buffer = try PixelBuffer(width: 4, height: 1)
        try buffer.setPixel(x: 0, y: 0, RGBA(r: 1, g: 1, b: 1, a: 1))
        let surface = try cpu.surface(buffer)
        for (amount, threshold) in [(.nan, 0), (.infinity, 0), (-.infinity, 0.1), (1, -1), (1, -0.001), (1, .nan),
                                    (1, .infinity), (.nan, -1), (1, 0)] as [(Double, Double)] {
            do {
                _ = try cpu.unsharpMask(surface, amount: amount, sigma: 1, threshold: threshold)
                #expect(throws: Never.self) { try UnsharpRule(amount: amount, threshold: threshold) }
            } catch let expected as RenderError {
                #expect(throws: expected) { try UnsharpRule(amount: amount, threshold: threshold) }
            }
        }
        let huge = try UnsharpRule(amount: 1e300, threshold: 0)
        do {
            _ = try cpu.unsharpMask(surface, amount: 1e300, sigma: 1, threshold: 0)
            Issue.record("the CPU accepts an overflowing amount")
        } catch let expected as RenderError {
            #expect(throws: expected) { try huge.check([0, huge.apply(1, blurred: 0.5)]) }
        }
        #expect(throws: Never.self) { try huge.check([0, 1, -2]) }
    }
}
